import 'dart:async';
import 'dart:convert';

import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart' as constants;
import 'format_utils.dart';
import 'jetstream_manager.dart';
import 'message_detail_dialog.dart';
import 'paused_banner.dart';
import 'regex_text_highlight.dart';

/// Live "Browse Messages" panel for a single JetStream stream.
///
/// Uses an ephemeral, auto-cleaning [OrderedConsumer] under the hood so the
/// user never has to think about consumer setup just to look at what's in a
/// stream — opening this panel starts the tail, closing it (or disposing)
/// tears the consumer down again. Mirrors the look and feel of the Live
/// Messages list in `main.dart` for visual consistency.
class JetStreamMessageView extends StatefulWidget {
  final String streamName;
  final JetStreamManager manager;
  final VoidCallback onClose;

  /// Fires after a real reconnect (not just a transient auto-reconnect
  /// blip) -- see `JetStreamDashboard`'s doc comment on the same parameter.
  /// Optional so existing call sites/tests that have nothing to notify this
  /// view about don't need to plumb one through.
  final Listenable? reconnectSignal;

  const JetStreamMessageView({
    super.key,
    required this.streamName,
    required this.manager,
    required this.onClose,
    this.reconnectSignal,
  });

  @override
  State<JetStreamMessageView> createState() => JetStreamMessageViewState();
}

class JetStreamMessageViewState extends State<JetStreamMessageView> {
  OrderedConsumer? _consumer;
  StreamSubscription<Message>? _subscription;
  final List<Message> _messages = [];
  List<Message> _filteredMessages = [];
  String? _errorMessage;

  String _currentFilter = '';
  String _currentFind = '';
  final _filterController = TextEditingController();
  final _findController = TextEditingController();
  final _filterFocusNode = FocusNode();
  final _findFocusNode = FocusNode();
  final _scrollController = ScrollController();

  // Whether the "jump to top" button should be shown — true once the user
  // has scrolled away from the top of the (newest-at-top) list.
  bool _showJumpToTop = false;

  // The fixed height of every message row, one line tall — see the matching
  // `_messageRowExtent` in `main.dart` for the full reasoning (fixed extent
  // lets `_insertMessages` compensate the scroll offset exactly, and lets
  // the scrollbar/fling locate rows analytically). Constant here (rather
  // than derived from a setting) since this view's rows always use font 14;
  // 56px is the same floor `main.dart` applies so the row stays tall enough
  // for the trailing controls' tap target (14 * 1.3 + 24 = 42.2 < 56).
  static const _messageRowExtent = 56.0;

  // Pause: while true, incoming messages are buffered here instead of
  // touching `_messages`/the rendered list at all.
  bool _paused = false;
  final List<Message> _pendingMessages = [];
  // Mirrors `_pendingMessages.length` for `PausedBanner`/the toolbar pill's
  // `ValueListenableBuilder` -- see the matching `_pendingCount` in
  // `main.dart` for the full reasoning (kept in sync inside the same
  // `setState`s here rather than replicating that file's no-`setState`
  // optimization, since this view's flush isn't rewritten to skip it).
  final ValueNotifier<int> _pendingCount = ValueNotifier<int>(0);

  // A stream can deliver far faster than the UI needs to reflect it —
  // incoming messages land here first (cheap O(1) append) and get flushed
  // into `_messages` at most once per `_incomingFlushInterval`.
  final List<Message> _incomingBatch = [];
  Timer? _incomingFlushTimer;
  static const _incomingFlushInterval = Duration(milliseconds: 32);

  // Read once at open time -- this view has no constructor-level settings
  // plumbing today, so a change made in Settings while this panel is
  // already open only takes effect the next time it's reopened.
  int _maxMessages = constants.defaultMaxMessages;

  /// Lets the app-wide Ctrl+F / Ctrl+Shift+F shortcut handler in `main.dart`
  /// reach this view's Find field via the `GlobalKey` held by
  /// `JetStreamDashboard` when this view is the one currently showing.
  void focusFindField() => _findFocusNode.requestFocus();

  /// See [focusFindField].
  void focusFilterField() => _filterFocusNode.requestFocus();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateJumpToTopVisibility);
    _loadMaxMessages();
    _startBrowsing();
    widget.reconnectSignal?.addListener(_onReconnect);
  }

  /// The underlying [OrderedConsumer] already recreates itself on its own
  /// after a real reconnect (it retries `createConsumer` internally, resuming
  /// from the last sequence seen -- see its doc comment in `dart_nats`), but
  /// this view has no way to notice that recovery happened on its own: once
  /// `_errorMessage` is set, nothing here ever clears it again, so the Retry
  /// banner would otherwise sit there forever hiding an already-healthy feed.
  /// Reuse the same `_retry()` a manual click would trigger rather than just
  /// clearing the flag, since the consumer needs recreating anyway (rather
  /// than assuming the exact moment of reconnect lines up with the
  /// consumer's own internal retry timing).
  void _onReconnect() {
    if (!mounted) return;
    if (_errorMessage != null) {
      _retry();
    }
  }

  Future<void> _loadMaxMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(constants.prefMaxMessages) ??
        constants.defaultMaxMessages;
    if (!mounted) return;
    setState(() => _maxMessages = value);
  }

  @override
  void didUpdateWidget(covariant JetStreamMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamName != widget.streamName) {
      _stopBrowsing();
      _messages.clear();
      _filteredMessages = [];
      _errorMessage = null;
      _pendingMessages.clear();
      _pendingCount.value = 0;
      _incomingBatch.clear();
      _incomingFlushTimer?.cancel();
      _incomingFlushTimer = null;
      _startBrowsing();
    }
  }

  @override
  void dispose() {
    widget.reconnectSignal?.removeListener(_onReconnect);
    _stopBrowsing();
    _incomingFlushTimer?.cancel();
    _pendingCount.dispose();
    _filterController.dispose();
    _findController.dispose();
    _filterFocusNode.dispose();
    _findFocusNode.dispose();
    _scrollController.removeListener(_updateJumpToTopVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  /// Tracks whether the list has scrolled away from the top so the "jump to
  /// top" button can be shown/hidden. Instant jump — nothing to animate.
  void _updateJumpToTopVisibility() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 1.0;
    if (show != _showJumpToTop) {
      setState(() => _showJumpToTop = show);
    }
  }

  void _jumpToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _startBrowsing() {
    final consumer = widget.manager.browseStream(widget.streamName);
    _consumer = consumer;
    _subscription = consumer.messages().listen(
      (message) {
        if (!mounted) return;
        // Cheap regardless of arrival rate: just buffer, then coalesce into
        // one UI update per `_incomingFlushInterval` (see the field doc).
        _incomingBatch.add(message);
        _incomingFlushTimer ??=
            Timer(_incomingFlushInterval, _flushIncomingMessages);
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = describeJetStreamError(err);
        });
      },
    );
  }

  void _flushIncomingMessages() {
    _incomingFlushTimer = null;
    if (!mounted || _incomingBatch.isEmpty) return;
    // `_incomingBatch` accumulates in arrival order (oldest of the batch
    // first); `_messages`/`_pendingMessages` are newest-first, so reverse it
    // once here rather than doing anything per-message.
    final newestFirst = _incomingBatch.reversed.toList(growable: false);
    _incomingBatch.clear();

    if (_paused) {
      setState(() {
        _pendingMessages.insertAll(0, newestFirst);
        // Cap the buffer the same way `_trimMessagesToCap` caps `_messages`
        // -- drop the oldest (tail) entries past the limit.
        if (_maxMessages > 0 && _pendingMessages.length > _maxMessages) {
          _pendingMessages.removeRange(_maxMessages, _pendingMessages.length);
        }
        _pendingCount.value = _pendingMessages.length;
      });
      return;
    }

    _insertMessages(newestFirst);
  }

  /// Inserts a newest-first batch at the front of `_messages`, keeping the
  /// user's view stable — see the matching `_insertMessages()` in
  /// `main.dart` for the full reasoning. In short: newest-at-top,
  /// top-anchored; at the top the new newest just appears above, and when
  /// scrolled away the offset is shifted down by exactly the height of the
  /// prepended rows (exact because every row is a fixed `_messageRowExtent`
  /// tall) so on-screen messages don't move.
  void _insertMessages(List<Message> newestFirst) {
    if (newestFirst.isEmpty) return;
    final hasClients = _scrollController.hasClients;
    final atTop = !hasClients || _scrollController.offset <= 1.0;
    final oldOffset = hasClients ? _scrollController.offset : 0.0;

    late final int addedToFiltered;
    setState(() {
      // Whether _filteredMessages IS _messages must be checked before the
      // insert: once no filter is active, _runFilter has aliased the two
      // lists, so insertAll grows "both" -- reading _filteredMessages.length
      // after the insert (as an older version did) then made
      // addedToFiltered compute to 0 and silently skipped the scroll
      // compensation below for every flush in the unfiltered case.
      final filterAliased = identical(_filteredMessages, _messages);
      _messages.insertAll(0, newestFirst);
      if (filterAliased) {
        addedToFiltered = newestFirst.length;
      } else {
        final oldFilteredLength = _filteredMessages.length;
        _runFilter();
        addedToFiltered = _filteredMessages.length - oldFilteredLength;
      }
      _trimMessagesToCap();
    });

    // Shift down by exactly the height of the rows actually added to
    // `_filteredMessages` (what's rendered), clamped to the new max so a
    // same-frame cap trim (which only removes rows below the viewport)
    // can't overshoot past the end of the now-shorter list.
    if (!atTop && addedToFiltered > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final newMax = _scrollController.position.maxScrollExtent;
        final target = oldOffset + addedToFiltered * _messageRowExtent;
        _scrollController.jumpTo(target > newMax ? newMax : target);
      });
    }
  }

  /// Trims `_messages` (and `_filteredMessages`) back down to `_maxMessages`,
  /// dropping the oldest messages first -- the tail of the newest-first
  /// list. `_maxMessages <= 0` means unlimited: no trimming ever happens.
  /// Must run inside the same `setState` that grew `_messages`.
  void _trimMessagesToCap() {
    if (_maxMessages <= 0 || _messages.length <= _maxMessages) return;
    final cutIndex = _maxMessages;
    final trimmed = _messages.sublist(cutIndex);
    _messages.removeRange(cutIndex, _messages.length);
    if (!identical(_filteredMessages, _messages)) {
      final trimmedSet = trimmed.toSet();
      _filteredMessages.removeWhere(trimmedSet.contains);
    }
  }

  void _pause() {
    setState(() => _paused = true);
  }

  void _resume() {
    final buffered = List<Message>.of(_pendingMessages);
    setState(() {
      _pendingMessages.clear();
      _paused = false;
    });
    _pendingCount.value = 0;
    _insertMessages(buffered);
  }

  void _clearMessages() {
    setState(() {
      _messages.clear();
      _filteredMessages = [];
      _pendingMessages.clear();
      _incomingBatch.clear();
    });
    _pendingCount.value = 0;
  }

  void _stopBrowsing() {
    _subscription?.cancel();
    _subscription = null;
    _consumer?.stop();
    _consumer = null;
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _messages.clear();
      _filteredMessages = [];
      _pendingMessages.clear();
      _incomingBatch.clear();
    });
    _pendingCount.value = 0;
    _incomingFlushTimer?.cancel();
    _incomingFlushTimer = null;
    _stopBrowsing();
    _startBrowsing();
  }

  void _runFilter() {
    if (_currentFilter.isEmpty) {
      _filteredMessages = _messages;
    } else {
      final lowerFilter = _currentFilter.toLowerCase();
      _filteredMessages = _messages
          .where((message) =>
              decodeMessageTextFor(message).toLowerCase().contains(lowerFilter))
          .toList();
    }
  }

  Future<void> _showDetailDialog(Message message) async {
    var headerVersion = '';
    Map<String, String> headers = <String, String>{};
    if (message.header != null) {
      headerVersion = message.header?.version ?? '';
      headers = message.header?.headers ?? <String, String>{};
    }

    final text = decodeMessageTextFor(message);
    String formattedJson;
    try {
      final json = jsonDecode(text);
      final encoder = const JsonEncoder.withIndent('    ');
      formattedJson = encoder.convert(json);
    } on FormatException {
      formattedJson = text;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => MessageDetailDialog(
        headerVersion: headerVersion,
        headers: headers,
        formattedJson: formattedJson,
        payloadBytes: message.byte,
      ),
    );
  }

  /// Centered icon+message, mirroring the pattern the JetStream/KV/Object
  /// Store dashboards already use for their own empty states.
  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rowEvenColor = isDark
        ? Color.alphaBlend(
            theme.colorScheme.surface.withAlpha(40), theme.colorScheme.surface)
        : Color.alphaBlend(
            theme.colorScheme.surface.withAlpha(20), theme.colorScheme.surface);
    final rowOddColor = isDark
        ? Color.alphaBlend(theme.colorScheme.secondaryContainer.withAlpha(80),
            theme.colorScheme.surface)
        : Color.alphaBlend(theme.colorScheme.secondaryContainer.withAlpha(140),
            theme.colorScheme.surface);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to stream details',
                onPressed: widget.onClose,
              ),
              Icon(Icons.circle,
                  size: 10,
                  color:
                      _paused ? Colors.grey.shade500 : Colors.green.shade400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Browsing: ${widget.streamName}',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_currentFilter.isEmpty
                  ? '${_messages.length} received'
                  : '${_filteredMessages.length} / ${_messages.length} shown'),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Clear',
                onPressed: _clearMessages,
              ),
              Tooltip(
                message: _paused
                    ? 'Resume (${_pendingMessages.length} buffered)'
                    : 'Pause incoming messages',
                // No fixed-width reservation here (unlike the equivalent
                // control in main.dart's bottom toolbar) — this is the last
                // item in the row, so there's nothing to its right that the
                // buffered-count pill's changing width could shift. A
                // `Badge` here used to overlap the icon closely enough that
                // it was hard to tell Pause from Resume at a glance without
                // the tooltip — a plain Row with the count as a separate
                // pill keeps the icon fully visible.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      onPressed: _paused ? _resume : _pause,
                    ),
                    if (_paused && _pendingMessages.isNotEmpty)
                      Text(
                        formatCompactCount(_pendingMessages.length),
                        overflow: TextOverflow.clip,
                        softWrap: false,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _filterController,
                  focusNode: _filterFocusNode,
                  onChanged: (value) {
                    setState(() {
                      _currentFilter = value;
                      _runFilter();
                    });
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Filter',
                    labelText: 'Filter',
                    prefixIcon: const Icon(Icons.filter_list),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _filterController.clear();
                          _currentFilter = '';
                          _runFilter();
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _findController,
                  focusNode: _findFocusNode,
                  onChanged: (value) {
                    setState(() {
                      _currentFind = value;
                    });
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'Find',
                    labelText: 'Find',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _findController.clear();
                          _currentFind = '';
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_paused)
          PausedBanner(
            pendingCount: _pendingCount,
            onResume: _resume,
          ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!)),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          )
        else if (_messages.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.hourglass_empty, 'Waiting for messages...'),
          )
        else if (_filteredMessages.isEmpty)
          Expanded(
            child: _buildEmptyState(
                Icons.search_off, 'No messages match filter.'),
          )
        else
          Expanded(
            child: Stack(
              children: [
                Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    // Newest-at-top, top-anchored — see the matching comment in
                    // `main.dart`'s `_buildLiveMessagesTab`. Stable scrolling on
                    // prepend is handled in `_insertMessages` via an exact
                    // offset shift, which relies on this fixed `itemExtent`.
                    itemExtent: _messageRowExtent,
                    itemCount: _filteredMessages.length,
                    itemBuilder: (context, index) {
                      final message = _filteredMessages[index];
                      final seq = message.streamSequence;
                      return Material(
                        key: ObjectKey(message),
                        child: ListTile(
                          // Tells ListTile the row's real fixed height, not
                          // just its own natural content height — see the
                          // matching `minTileHeight` in `main.dart` for why
                          // this matters for centering.
                          minTileHeight: _messageRowExtent,
                          // Band by distance from the oldest message (always at
                          // the bottom), not the raw index, so stripes don't
                          // flip every time a message is prepended at the top.
                          tileColor:
                              (_filteredMessages.length - 1 - index) % 2 == 0
                                  ? rowEvenColor
                                  : rowOddColor,
                          title: RegexTextHighlight(
                            text: decodeMessageTextFor(message),
                            searchTerm: _currentFind,
                            fontSize: 14,
                            highlightStyle: TextStyle(
                              background: Paint()
                                ..color = theme.colorScheme.inversePrimary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _showDetailDialog(message),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (seq != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 0, 5, 0),
                                  child: Chip(label: Text('#$seq')),
                                ),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 300),
                                child: Tooltip(
                                  message: message.subject ?? '',
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 5, 0),
                                    child: Chip(
                                      label: Text(
                                        message.subject ?? '',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                tooltip: 'More actions',
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'copy', child: Text('Copy')),
                                  PopupMenuItem(
                                      value: 'copy_subject',
                                      child: Text('Copy Subject')),
                                  PopupMenuItem(
                                      value: 'detail', child: Text('Detail')),
                                ],
                                onSelected: (value) {
                                  switch (value) {
                                    case 'copy':
                                      Clipboard.setData(ClipboardData(
                                          text: decodeMessageTextFor(message)));
                                      break;
                                    case 'copy_subject':
                                      Clipboard.setData(ClipboardData(
                                          text: message.subject ?? ''));
                                      break;
                                    case 'detail':
                                      _showDetailDialog(message);
                                      break;
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_showJumpToTop)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      mini: true,
                      tooltip: 'Jump to top',
                      onPressed: _jumpToTop,
                      child: const Icon(Icons.vertical_align_top),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
