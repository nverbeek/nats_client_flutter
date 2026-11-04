import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_info_dialog.dart';
import 'connections_table.dart';
import 'format_utils.dart';
import 'jetstream_manager.dart';
import 'server_monitor.dart';
import 'throughput_chart.dart';

/// Tab body widths where the layout changes: below [wideMinWidth] the
/// identity panel moves behind a "Details" toggle, and below
/// [mediumMinWidth] everything stacks into one column.
const double wideMinWidth = 1100;
const double mediumMinWidth = 750;

enum _Layout { wide, medium, narrow }

/// Server tab content: the connected server's identity, load, throughput
/// and connections, polled from its HTTP monitoring endpoint.
///
/// Polls only while mounted. `TabBarView` disposes tabs that aren't
/// showing, so leaving the tab stops all requests; the chart's history
/// lives in the [ServerMonitorSession] instead, so it survives that.
class ServerMonitorDashboard extends StatefulWidget {
  const ServerMonitorDashboard({
    super.key,
    required this.session,
    this.reconnectSignal,
    this.pollInterval = const Duration(seconds: 2),
    this.accountInfoManager,
    this.onOpenSettings,
  });

  /// `null` when not connected.
  final ServerMonitorSession? session;

  /// Fires after a real reconnect; an endpoint that failed is retried at
  /// once. See `JetStreamDashboard`'s doc comment on the same parameter.
  final Listenable? reconnectSignal;
  final Duration pollInterval;

  /// For the Account Info button, which reuses JetStream's dialog.
  final JetStreamManager? accountInfoManager;

  /// Opens Settings, for the "Change port" button.
  final VoidCallback? onOpenSettings;

  @override
  State<ServerMonitorDashboard> createState() => ServerMonitorDashboardState();
}

class ServerMonitorDashboardState extends State<ServerMonitorDashboard> {
  /// `/connz`, `/healthz` and `/gatewayz` are fetched every this many polls:
  /// `/connz` makes the server collect and sort every connection, even for
  /// one page, so polling it as often as `/varz` would load busy servers.
  static const int slowEvery = 5;

  /// How often to retry while the endpoint has never answered.
  static const Duration retryInterval = Duration(seconds: 10);

  ServerVarz? _varz;
  HealthStatus? _health;
  int? _gatewayCount;
  ConnzPage? _connz;
  Object? _connzError;
  Object? _error;
  DateTime? _updatedAt;

  Timer? _timer;

  /// The session a poll is running for. A poll for a session that has
  /// since been replaced doesn't hold up the new one's.
  ServerMonitorSession? _polling;
  bool _connzStale = false;
  int _tick = 0;
  bool _paused = false;

  /// Bumped whenever the sort, page or page size changes, so a `/connz`
  /// page fetched for the previous one is dropped.
  int _connzQuery = 0;

  /// How long the last poll took, all its requests included.
  Duration _lastPollTook = Duration.zero;

  ConnzSort _sort = ConnzSort.msgsTo;
  int _offset = 0;
  int _limit = 25;
  bool _bytes = false;
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    widget.reconnectSignal?.addListener(_onReconnect);
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.reconnectSignal?.removeListener(_onReconnect);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServerMonitorDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reconnectSignal != widget.reconnectSignal) {
      oldWidget.reconnectSignal?.removeListener(_onReconnect);
      widget.reconnectSignal?.addListener(_onReconnect);
    }
    if (oldWidget.session != widget.session) {
      _timer?.cancel();
      setState(() {
        _varz = null;
        _health = null;
        _gatewayCount = null;
        _connz = null;
        _connzError = null;
        _error = null;
        _updatedAt = null;
        _tick = 0;
        _offset = 0;
        _connzQuery++;
        _connzStale = false;
        _lastPollTook = Duration.zero;
      });
      _poll();
    } else if (oldWidget.pollInterval != widget.pollInterval && !_paused) {
      _schedule();
    }
  }

  void _onReconnect() {
    if (mounted && _error != null && !_paused) _poll();
  }

  /// Schedules the next poll: [ServerMonitorDashboard.pollInterval] apart
  /// once the endpoint has answered, [retryInterval] until it does,
  /// counted from when the last poll started ([took] is how long it ran).
  /// A one-shot timer started after each poll finishes, so polls never
  /// overlap however slow the server is.
  void _schedule([Duration took = Duration.zero]) {
    _timer?.cancel();
    if (_paused || widget.session == null) return;
    final wait = (_varz == null ? retryInterval : widget.pollInterval) - took;
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _poll);
  }

  Future<void> _poll({bool connzNow = false}) async {
    final session = widget.session;
    if (session == null) return;
    if (_polling == session) {
      if (connzNow) _connzStale = true;
      return;
    }
    _polling = session;
    _timer?.cancel();
    final started = DateTime.now();
    final slow = _tick % slowEvery == 0;
    _tick++;
    final client = session.client;
    try {
      final varz = await client.fetchVarz();
      if (!mounted || widget.session != session) return;
      // Polls start pollInterval apart unless one takes longer than that.
      session.history.add(varz,
          interval: _lastPollTook > widget.pollInterval
              ? _lastPollTook
              : widget.pollInterval);
      // Each of these can fail without the others, or a good /varz, being
      // thrown away: a slow /connz, a busy JetStream server's /healthz, or
      // a server too old to have /healthz.
      final query = _connzQuery;
      final (connz, health, gateways) = await (
        _attempt(
            slow || connzNow || _connz == null,
            () =>
                client.fetchConnz(sort: _sort, offset: _offset, limit: _limit)),
        _attempt(slow, client.fetchHealth),
        _attempt(slow && varz.gatewayName != null, client.fetchGatewayCount),
      ).wait;
      if (!mounted || widget.session != session) return;
      setState(() {
        _varz = varz;
        // A page for an earlier sort or page is dropped; the poll that
        // the change asked for (_connzStale) brings the right one.
        if (connz != null && query == _connzQuery) {
          final page = connz.value;
          _connzError = connz.error;
          if (page != null) {
            _connz = page;
            // Connections closed since the user paged here: go to the
            // last page there is.
            if (page.connections.isEmpty && page.total > 0 && _offset > 0) {
              _offset = (page.total - 1) ~/ _limit * _limit;
              _connz = null;
              _connzQuery++;
              _connzStale = true;
            }
          }
        }
        // A failed /healthz hides the pill rather than keep an old answer.
        if (health != null) _health = health.value;
        if (varz.gatewayName == null) {
          _gatewayCount = 0;
        } else if (gateways?.value != null) {
          _gatewayCount = gateways!.value;
        }
        _error = null;
        _updatedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted || widget.session != session) return;
      setState(() => _error = e);
    } finally {
      if (_polling == session) _polling = null;
    }
    if (!mounted || widget.session != session) return;
    _lastPollTook = DateTime.now().difference(started);
    if (_connzStale) {
      _connzStale = false;
      unawaited(_poll(connzNow: true));
    } else {
      _schedule(_lastPollTook);
    }
  }

  /// Runs [fetch] when [wanted], catching its error; null when not wanted.
  static Future<_Outcome<T>?> _attempt<T>(
      bool wanted, Future<T> Function() fetch) async {
    if (!wanted) return null;
    try {
      return _Outcome.value(await fetch());
    } catch (e) {
      return _Outcome.error(e);
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
    } else {
      _poll();
    }
  }

  void _setConnzQuery({ConnzSort? sort, int? offset, int? limit}) {
    setState(() {
      if (sort != null && sort != _sort) {
        _sort = sort;
        _offset = 0;
      }
      if (limit != null && limit != _limit) {
        _limit = limit;
        _offset = 0;
      }
      if (offset != null) _offset = offset;
      _connz = null;
      _connzError = null;
      _connzQuery++;
    });
    _poll(connzNow: true);
  }

  void _showAccountInfo() {
    final manager = widget.accountInfoManager;
    if (manager == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AccountInfoDialog(
        initial: manager.lastAccountInfo,
        onRefresh: manager.fetchAccountInfo,
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) {
      return _emptyState(Icons.cloud_off,
          "Connect to a NATS server to see its monitoring data.");
    }
    final varz = _varz;
    if (varz == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : _unreachable(session);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final layout = constraints.maxWidth >= wideMinWidth
          ? _Layout.wide
          : constraints.maxWidth >= mediumMinWidth
              ? _Layout.medium
              : _Layout.narrow;
      final main = _mainPanel(context, session, varz, layout);
      if (layout != _Layout.wide) return main;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 300, child: _sidePanel(context, session, varz)),
          const VerticalDivider(width: 1),
          Expanded(child: main),
        ],
      );
    });
  }

  Widget _emptyState(IconData icon, String message, {Widget? action}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }

  /// The endpoint has never answered.
  Widget _unreachable(ServerMonitorSession session) {
    final theme = Theme.of(context);
    final error = _error;
    final kind = error is MonitorException ? error.kind : null;
    final portProblem = kind == MonitorErrorKind.unreachable ||
        kind == MonitorErrorKind.notMonitoring;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.disabledColor),
              const SizedBox(height: 12),
              Text("Can't reach the monitoring endpoint",
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(describeMonitorError(error!, session.endpoint),
                  textAlign: TextAlign.center),
              if (portProblem) ...[
                const SizedBox(height: 8),
                Text(
                  'The NATS connection itself is fine. Monitoring is a '
                  'separate HTTP port that nats-server only opens when '
                  'started with -m 8222, or with http_port: 8222 in its '
                  'config.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _poll,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry now'),
                  ),
                  if (widget.onOpenSettings != null)
                    OutlinedButton(
                      onPressed: widget.onOpenSettings,
                      child: const Text('Change port'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _paused
                    ? 'Retrying is paused.'
                    : 'Retrying every ${retryInterval.inSeconds} seconds.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------- wide side panel

  Widget _sidePanel(
      BuildContext context, ServerMonitorSession session, ServerVarz varz) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Text('Server', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        _section(context, 'Identity', [
          _identity(context, varz),
          if (_accountInfoAvailable(varz)) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _showAccountInfo,
                icon: const Icon(Icons.bar_chart),
                label: const Text('Account Info'),
              ),
            ),
          ],
        ]),
        const Divider(height: 1),
        _section(context, 'Topology', [
          _topologyRow('Routes', 'Cluster peers', varz.routes),
          _topologyRow('Gateways', 'Other clusters', _gatewayCount),
          _topologyRow('Leaf nodes', 'Edge servers', varz.leafnodes),
        ]),
        const Divider(height: 1),
        _section(context, 'Monitoring endpoint', [_endpoint(context, session)]),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _topologyRow(String label, String hint, int? count) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(hint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(count == null ? '…' : '$count',
              style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _endpoint(BuildContext context, ServerMonitorSession session) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(session.endpoint.label,
            style: const TextStyle(fontFamily: 'monospace')),
        const SizedBox(height: 4),
        Text('Host comes from the connection, port from Settings.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }

  bool _accountInfoAvailable(ServerVarz varz) =>
      varz.jetStreamEnabled && widget.accountInfoManager != null;

  /// Server identity from `/varz`, as label/value rows.
  Widget _identity(BuildContext context, ServerVarz varz) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    TableRow row(String label, Widget value) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 6),
            child: Text(label, style: labelStyle),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: value),
        ]);
    final start = varz.start;
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        row('Name', Text(varz.serverName.isEmpty ? '—' : varz.serverName)),
        row(
          'ID',
          Row(
            children: [
              Expanded(
                child: Text(varz.serverId,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
              IconButton(
                tooltip: 'Copy server ID',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: varz.serverId)),
              ),
            ],
          ),
        ),
        row('Version', Text(varz.version)),
        row('Go', Text(varz.goVersion)),
        row('Host', Text('${varz.host}:${varz.port}')),
        if (start != null) row('Started', Text(_startedLabel(start.toLocal()))),
        row('Uptime', _UptimeText(varz: varz, fetchedAt: _updatedAt)),
        row(
            'JetStream',
            Text(!varz.jetStreamEnabled
                ? 'Off'
                : varz.jetStreamDomain == null
                    ? 'Enabled'
                    : 'Enabled · domain ${varz.jetStreamDomain}')),
        row(
            'Cluster',
            Text(varz.clusterName == null
                ? 'None'
                : '${varz.clusterName} · ${varz.routes} '
                    '${varz.routes == 1 ? 'route' : 'routes'}')),
        row('Max payload', Text(formatBytes(varz.maxPayload))),
        row(
            'Auth / TLS',
            Text('${varz.authRequired ? 'Required' : 'Off'} / '
                '${varz.tlsRequired ? 'Required' : 'Off'}')),
      ],
    );
  }

  // ------------------------------------------------------------ main panel

  Widget _mainPanel(BuildContext context, ServerMonitorSession session,
      ServerVarz varz, _Layout layout) {
    final compact = layout != _Layout.wide;
    final padding = layout == _Layout.narrow ? 12.0 : 20.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, 16, padding, 20),
      children: [
        _header(context, varz, layout),
        if (compact && _detailsOpen) ...[
          const SizedBox(height: 12),
          _detailsCard(context, session, varz, layout),
        ],
        const SizedBox(height: 16),
        _tiles(context, varz, layout),
        const SizedBox(height: 16),
        _throughputCard(context, session),
        const SizedBox(height: 16),
        _connectionsCard(context, layout),
      ],
    );
  }

  /// The server's name and status pills on the left, and how fresh the data
  /// is plus the actions on the right. On a narrow tab the actions get a row
  /// of their own, with "Updated" at its left.
  Widget _header(BuildContext context, ServerVarz varz, _Layout layout) {
    final theme = Theme.of(context);
    final compact = layout != _Layout.wide;
    final health = _health;
    final error = _error;
    final status = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(varz.serverName.isEmpty ? varz.serverId : varz.serverName,
            style: theme.textTheme.titleLarge),
        if (health != null)
          _Pill(
            dot: health.ok ? Colors.green : theme.colorScheme.error,
            label: health.ok ? 'Healthy' : 'Unhealthy',
            tooltip: health.error,
          ),
        _Pill(label: 'v${varz.version}'),
        if (compact)
          _Pill(
              child: _UptimeText(
                  varz: varz,
                  fetchedAt: _updatedAt,
                  prefix: 'Up ',
                  short: true)),
        _Pill(
          dot: _paused ? theme.colorScheme.outline : Colors.green,
          label: _paused
              ? 'Polling paused'
              : 'Polling every ${widget.pollInterval.inSeconds}s',
        ),
      ],
    );
    final freshness = error != null
        ? Tooltip(
            message: describeMonitorError(error, widget.session!.endpoint),
            child: Text('Last update failed',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          )
        : _UpdatedText(updatedAt: _updatedAt);
    final actions = <Widget>[
      if (compact)
        TextButton.icon(
          key: const ValueKey('serverDetailsToggle'),
          onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
          icon: Icon(_detailsOpen ? Icons.expand_less : Icons.expand_more),
          label: const Text('Details'),
        ),
      if (compact && _accountInfoAvailable(varz))
        IconButton(
          tooltip: 'Account info',
          onPressed: _showAccountInfo,
          icon: const Icon(Icons.bar_chart),
        ),
      IconButton(
        tooltip: _paused ? 'Resume polling' : 'Pause polling',
        onPressed: _togglePause,
        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
      ),
      IconButton(
        tooltip: 'Refresh now',
        onPressed: () => _poll(connzNow: true),
        icon: const Icon(Icons.refresh),
      ),
    ];
    if (layout == _Layout.narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status,
          const SizedBox(height: 4),
          Row(children: [freshness, const Spacer(), ...actions]),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: status),
        const SizedBox(width: 12),
        freshness,
        const SizedBox(width: 6),
        ...actions,
      ],
    );
  }

  /// Medium and narrow: the identity panel, behind the Details toggle.
  Widget _detailsCard(BuildContext context, ServerMonitorSession session,
      ServerVarz varz, _Layout layout) {
    final identity = _identity(context, varz);
    final endpoint =
        _section(context, 'Monitoring endpoint', [_endpoint(context, session)]);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: layout == _Layout.narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [identity, endpoint],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 24),
                  Expanded(child: endpoint),
                ],
              ),
      ),
    );
  }

  Widget _tiles(BuildContext context, ServerVarz varz, _Layout layout) {
    final tiles = <Widget>[
      _Tile(
          label: 'Connections',
          value: formatGroupedCount(varz.connections),
          sub: 'clients'),
      _Tile(
          label: 'Subscriptions',
          value: formatGroupedCount(varz.subscriptions),
          sub: 'across all accounts'),
      _Tile(
          label: 'CPU',
          value: '${varz.cpu.toStringAsFixed(1)}%',
          sub: '${varz.cores} ${varz.cores == 1 ? 'core' : 'cores'}'),
      _Tile(label: 'Memory', value: formatBytes(varz.mem), sub: 'resident'),
    ];
    final topology = _Tile(
      label: 'Topology',
      value: '${varz.routes} · ${_gatewayCount ?? '…'} · ${varz.leafnodes}',
      sub: 'routes · gateways · leaf nodes',
    );
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 12.0;
      final width = constraints.maxWidth;
      if (layout == _Layout.narrow) {
        final half = (width - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: half, child: t),
            SizedBox(width: width, child: topology),
          ],
        );
      }
      final all = [...tiles, if (layout == _Layout.medium) topology];
      final each = (width - gap * (all.length - 1)) / all.length;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in all) SizedBox(width: each, child: t)],
      );
    });
  }

  Widget _throughputCard(BuildContext context, ServerMonitorSession session) {
    final theme = Theme.of(context);
    final samples = session.history.samples;
    final last = samples.isEmpty ? null : samples.last;
    Widget legend(Color color, String label, double? value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 3, color: color),
            const SizedBox(width: 6),
            Text('$label '),
            Text(
              value == null ? '–' : formatThroughputRate(value, bytes: _bytes),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        );
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Throughput', style: theme.textTheme.titleSmall),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style:
                      const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: false, label: Text('Messages')),
                    ButtonSegment(value: true, label: Text('Bytes')),
                  ],
                  selected: {_bytes},
                  onSelectionChanged: (s) => setState(() => _bytes = s.first),
                ),
                legend(
                    throughputInColor(theme.brightness),
                    'In',
                    last == null
                        ? null
                        : (_bytes ? last.inBytes : last.inMsgs)),
                legend(
                    throughputOutColor(theme.brightness),
                    'Out',
                    last == null
                        ? null
                        : (_bytes ? last.outBytes : last.outMsgs)),
              ],
            ),
            const SizedBox(height: 8),
            ThroughputChart(
              samples: samples,
              version: session.history.version,
              bytes: _bytes,
            ),
            const SizedBox(height: 4),
            Text(
              'The server reports running totals, so rates come from the '
              'change between two polls. The chart fills in over its first '
              '2 minutes.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionsCard(BuildContext context, _Layout layout) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConnectionsTable(
        page: _connz,
        error: _connzError == null
            ? null
            : describeMonitorError(_connzError!, widget.session!.endpoint),
        sort: _sort,
        offset: _offset,
        limit: _limit,
        narrow: layout == _Layout.narrow,
        onSort: (s) => _setConnzQuery(sort: s),
        onOffset: (o) => _setConnzQuery(offset: o),
        onLimit: (l) => _setConnzQuery(limit: l),
      ),
    );
  }
}

/// A request's result or its error.
class _Outcome<T> {
  _Outcome.value(T this.value) : error = null;
  _Outcome.error(Object this.error) : value = null;

  final T? value;
  final Object? error;
}

/// `2026-11-04 07:44`: when the server started, to the minute. Uptime
/// below it carries the seconds.
String _startedLabel(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.sub});
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: muted),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall),
            Text(sub,
                style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({this.label, this.child, this.dot, this.tooltip});
  final String? label;
  final Widget? child;
  final Color? dot;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          child ?? Text(label ?? '', style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Rebuilds only itself once a second, so ticking text doesn't rebuild the
/// whole tab.
abstract class _EverySecondState<T extends StatefulWidget> extends State<T> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The server's uptime, counting on between polls.
class _UptimeText extends StatefulWidget {
  const _UptimeText(
      {required this.varz,
      required this.fetchedAt,
      this.prefix = '',
      this.short = false});
  final ServerVarz varz;
  final DateTime? fetchedAt;
  final String prefix;

  /// Two units (`3d 4h`) instead of four (`3d 4h 12m 08s`).
  final bool short;

  @override
  State<_UptimeText> createState() => _UptimeTextState();
}

class _UptimeTextState extends _EverySecondState<_UptimeText> {
  @override
  Widget build(BuildContext context) {
    final base = widget.varz.uptime;
    if (base == null) return Text('${widget.prefix}—');
    final fetchedAt = widget.fetchedAt;
    final uptime =
        fetchedAt == null ? base : base + DateTime.now().difference(fetchedAt);
    final text = widget.short
        ? formatConfiguredDuration(uptime)
        : '${uptime.inDays}d ${uptime.inHours % 24}h '
            '${(uptime.inMinutes % 60).toString().padLeft(2, '0')}m '
            '${(uptime.inSeconds % 60).toString().padLeft(2, '0')}s';
    return Text('${widget.prefix}$text',
        style: widget.short ? Theme.of(context).textTheme.bodySmall : null);
  }
}

/// "Updated just now" / "Updated 12s ago".
class _UpdatedText extends StatefulWidget {
  const _UpdatedText({required this.updatedAt});
  final DateTime? updatedAt;

  @override
  State<_UpdatedText> createState() => _UpdatedTextState();
}

class _UpdatedTextState extends _EverySecondState<_UpdatedText> {
  @override
  Widget build(BuildContext context) {
    final updatedAt = widget.updatedAt;
    if (updatedAt == null) return const SizedBox.shrink();
    final ago = DateTime.now().difference(updatedAt);
    return Text(
      ago.inSeconds < 2
          ? 'Updated just now'
          : 'Updated ${formatConfiguredDuration(ago)} ago',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
