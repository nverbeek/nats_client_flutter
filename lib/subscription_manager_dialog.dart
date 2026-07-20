import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'color_tab_chip.dart';
import 'subject_chip_style.dart';
import 'subscription_info.dart';

/// Ctrl+Enter (Cmd+Enter on Mac) submits [SubscriptionEditDialog] from
/// either field, not just the queue-group field's plain-Enter submit --
/// mirrors the same `Shortcuts`/`Actions` pattern `SendMessageDialog` uses
/// for its own Ctrl+Enter-to-send shortcut.
class _SubscriptionSubmitIntent extends Intent {
  const _SubscriptionSubmitIntent();
}

/// Add/edit form for a single subscription. In "add" mode (no [existing])
/// both fields are editable. In "edit" mode the subject is locked -- there's
/// no wire-level way to rename a live subscription, so changing the subject
/// is modeled as remove-then-add rather than an in-place edit; only the
/// queue group and a Remove action are exposed.
class SubscriptionEditDialog extends StatefulWidget {
  final SubscriptionInfo? existing;
  final void Function(String subject, String? queueGroup) onSave;
  final VoidCallback? onRemove;

  const SubscriptionEditDialog({
    super.key,
    this.existing,
    required this.onSave,
    this.onRemove,
  });

  @override
  State<SubscriptionEditDialog> createState() => _SubscriptionEditDialogState();
}

class _SubscriptionEditDialogState extends State<SubscriptionEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subjectController;
  late final TextEditingController _queueGroupController;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _subjectController =
        TextEditingController(text: widget.existing?.subject ?? '');
    _queueGroupController =
        TextEditingController(text: widget.existing?.queueGroup ?? '');
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _queueGroupController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final queueGroup = _queueGroupController.text.trim();
    widget.onSave(
      _subjectController.text.trim(),
      queueGroup.isEmpty ? null : queueGroup,
    );
    Navigator.of(context).pop();
  }

  void _remove() {
    widget.onRemove?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const _SubscriptionSubmitIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter):
            const _SubscriptionSubmitIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SubscriptionSubmitIntent: CallbackAction<_SubscriptionSubmitIntent>(
            onInvoke: (_SubscriptionSubmitIntent intent) {
              _submit();
              return null;
            },
          ),
        },
        child: AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_isEdit ? 'Edit Subscription' : 'Add Subscription'),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _subjectController,
                    enabled: !_isEdit,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Subject',
                      hintText: 'e.g. orders.*',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Subject is required'
                            : null,
                    autofocus: !_isEdit,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _queueGroupController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Queue group (optional)',
                      hintText: 'e.g. workers',
                    ),
                    autofocus: _isEdit,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (_isEdit)
              TextButton(
                onPressed: _remove,
                child: Text('Remove',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _submit,
              child: Text(_isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full subscription list-management dialog -- the overflow destination once
/// the toolbar's chip row runs out of width, and the general "see everything
/// at once" surface. Modeled on send_message_dialog.dart's header-row list
/// (key/value TextEditingControllers per row, disposed together), not
/// kv_bucket_dialog.dart (a single-entry create form despite its name).
class SubscriptionManagerDialog extends StatefulWidget {
  final List<SubscriptionInfo> subscriptions;
  final bool isDark;
  final bool showSubscriptionColors;
  final void Function(String subject, String? queueGroup) onAdd;
  final void Function(SubscriptionInfo info) onRemove;
  final void Function(SubscriptionInfo info, String? newQueueGroup)
      onQueueGroupChanged;

  const SubscriptionManagerDialog({
    super.key,
    required this.subscriptions,
    required this.isDark,
    required this.showSubscriptionColors,
    required this.onAdd,
    required this.onRemove,
    required this.onQueueGroupChanged,
  });

  @override
  State<SubscriptionManagerDialog> createState() =>
      _SubscriptionManagerDialogState();
}

class _SubscriptionManagerDialogState extends State<SubscriptionManagerDialog> {
  final Map<SubscriptionInfo, TextEditingController> _controllers = {};
  final Map<SubscriptionInfo, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant SubscriptionManagerDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  // Queue-group edits commit on blur/submit, not per keystroke -- each one
  // triggers an unsub+resub over the wire when connected, so we don't want
  // to spam that on every character typed.
  void _syncControllers() {
    for (final info in widget.subscriptions) {
      _controllers.putIfAbsent(
          info, () => TextEditingController(text: info.queueGroup ?? ''));
      _focusNodes.putIfAbsent(info, () {
        final node = FocusNode();
        node.addListener(() {
          if (!node.hasFocus) _commit(info);
        });
        return node;
      });
    }
    final stale = _controllers.keys
        .where((info) => !widget.subscriptions.contains(info))
        .toList();
    for (final info in stale) {
      _controllers.remove(info)?.dispose();
      _focusNodes.remove(info)?.dispose();
    }
  }

  void _commit(SubscriptionInfo info) {
    final controller = _controllers[info];
    if (controller == null) return;
    final newValue = controller.text.trim();
    if (newValue != (info.queueGroup ?? '')) {
      widget.onQueueGroupChanged(info, newValue.isEmpty ? null : newValue);
      // widget.subscriptions is the same mutable List the parent holds, so
      // the callback above already updated it -- but this dialog is a
      // separate Navigator route, not part of _MyHomePageState's own build
      // subtree, so its setState() doesn't reach us. Force our own rebuild
      // to actually show the change.
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _openAddDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => SubscriptionEditDialog(
        onSave: (subject, queueGroup) {
          widget.onAdd(subject, queueGroup);
          setState(() {}); // see _commit's comment on why this is needed
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Manage Subscriptions'),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Subscriptions',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openAddDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: widget.subscriptions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No subscriptions'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.subscriptions.length,
                      itemBuilder: (context, index) {
                        final info = widget.subscriptions[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                // Tooltip'd unconditionally (not just when
                                // actually truncated) -- Chip's internal
                                // label/content padding isn't something this
                                // widget can precisely know (same reasoning
                                // as ColorTabChip's corner-radius comment
                                // above), so replicating its exact overflow
                                // math to gate the tooltip would be fragile.
                                // Showing it always is harmless when the
                                // subject already fits.
                                child: Tooltip(
                                  message: info.subject,
                                  child: ColorTabChip(
                                    color: widget.showSubscriptionColors
                                        ? resolveSubscriptionColor(
                                            info.colorIndex, widget.isDark)
                                        : null,
                                    chip: Chip(
                                      label: Text(info.subject,
                                          overflow: TextOverflow.ellipsis),
                                      labelStyle:
                                          SubjectChipStyle.labelStyleFor(
                                              context),
                                      backgroundColor:
                                          SubjectChipStyle.backgroundColorFor(
                                              context),
                                      side: SubjectChipStyle.side,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _controllers[info],
                                  focusNode: _focusNodes[info],
                                  maxLines: 1,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    hintText: 'Queue group',
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                  ),
                                  onFieldSubmitted: (_) => _commit(info),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  widget.onRemove(info);
                                  setState(() {}); // see _commit's comment
                                },
                                tooltip: 'Remove subscription',
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
