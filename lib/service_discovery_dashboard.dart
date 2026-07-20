import 'package:dart_nats/dart_nats.dart' hide Consumer;
import 'package:flutter/material.dart';

import 'jetstream_manager.dart' show formatRelativeTime;
import 'service_discovery_manager.dart';

/// Services tab content: fan-out discovery of NATS Microservices (ADR-32)
/// currently running on the account, mirroring `ObjectStoreDashboard`'s
/// master/detail shape and its "no live watch — explicit action" pattern.
///
/// Unlike JetStream/KV/Object Store, there's no availability check and
/// nothing to list on load: every result here is itself the reply to an
/// explicit fan-out request the user triggers with the Discover button.
class ServiceDiscoveryDashboard extends StatefulWidget {
  /// The active discovery manager, or `null` when not currently connected.
  final ServiceDiscoveryManager? manager;

  /// Fires after a real reconnect -- see `JetStreamDashboard`'s doc comment
  /// on the same parameter. Optional so tests that never disconnect don't
  /// need to plumb one through.
  final Listenable? reconnectSignal;

  const ServiceDiscoveryDashboard(
      {super.key, required this.manager, this.reconnectSignal});

  @override
  State<ServiceDiscoveryDashboard> createState() =>
      ServiceDiscoveryDashboardState();
}

class ServiceDiscoveryDashboardState extends State<ServiceDiscoveryDashboard> {
  bool _discovering = false;
  bool _hasDiscovered = false;
  String? _discoverError;
  List<PingResponse> _services = [];

  PingResponse? _selected;
  bool _loadingDetail = false;
  String? _detailError;
  InfoResponse? _info;
  StatsResponse? _stats;

  @override
  void initState() {
    super.initState();
    widget.reconnectSignal?.addListener(_onReconnect);
  }

  @override
  void dispose() {
    widget.reconnectSignal?.removeListener(_onReconnect);
    super.dispose();
  }

  /// Recovers the error states a disconnect can strand this tab in. Unlike
  /// the JetStream/KV dashboards this deliberately doesn't re-run a
  /// successful discovery: every result here is the reply to an explicit
  /// user-triggered fan-out (see the class doc), so silently re-issuing one
  /// would break that contract. A *failed* discover or detail load is a
  /// different matter -- that's the stuck-on-Retry state the reconnect
  /// signal exists to clear.
  void _onReconnect() {
    if (!mounted || widget.manager == null) return;
    if (_discoverError != null) {
      _discover();
    }
    final selected = _selected;
    if (_detailError != null && selected != null) {
      _loadDetail(selected);
    }
  }

  @override
  void didUpdateWidget(covariant ServiceDiscoveryDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager == widget.manager) return;

    setState(() {
      _discovering = false;
      _hasDiscovered = false;
      _discoverError = null;
      _services = [];
      _selected = null;
      _loadingDetail = false;
      _detailError = null;
      _info = null;
      _stats = null;
    });
  }

  Future<void> _discover() async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _discovering = true;
      _discoverError = null;
    });

    try {
      final services = await manager.discover();
      if (!mounted || widget.manager != manager) return;
      services.sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
      setState(() {
        _services = services;
        _hasDiscovered = true;
        _discovering = false;
        // A prior selection may no longer be present in a fresh discovery
        // pass (the instance could have stopped) — that's fine, the detail
        // pane's own Refresh will surface it as "no longer responding"
        // rather than silently showing stale data next to a vanished row.
      });
    } catch (e) {
      if (!mounted || widget.manager != manager) return;
      setState(() {
        _discoverError = describeServiceDiscoveryError(e);
        _discovering = false;
      });
    }
  }

  Future<void> _selectService(PingResponse service) async {
    setState(() {
      _selected = service;
      _info = null;
      _stats = null;
      _detailError = null;
    });
    await _loadDetail(service);
  }

  Future<void> _loadDetail(PingResponse service) async {
    final manager = widget.manager;
    if (manager == null) return;

    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });

    try {
      final info = await manager.fetchInfo(service.name, service.id);
      final stats = await manager.fetchStats(service.name, service.id);
      if (!mounted || widget.manager != manager || _selected != service) {
        return;
      }
      setState(() {
        _info = info;
        _stats = stats;
        _loadingDetail = false;
        if (info == null && stats == null) {
          _detailError = '"${service.name}" is no longer responding — it '
              'may have stopped since the last Discover.';
        }
      });
    } catch (e) {
      if (!mounted || widget.manager != manager || _selected != service) {
        return;
      }
      setState(() {
        _detailError = describeServiceDiscoveryError(e);
        _loadingDetail = false;
      });
    }
  }

  Widget _buildEmptyState(IconData icon, String message, {Widget? action}) {
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

  Widget _buildServiceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Services',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                key: const ValueKey('discoverServicesButton'),
                icon: const Icon(Icons.travel_explore),
                label: const Text('Discover'),
                onPressed: _discovering ? null : _discover,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Discovery fans a request out to every running NATS '
            'Microservice (ADR-32) and collects replies for a short window '
            '— it\'s a snapshot, not a live view. Run Discover again to refresh.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
        const Divider(height: 1),
        if (_discovering)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_discoverError != null)
          Expanded(
            child: _buildEmptyState(
              Icons.error_outline,
              _discoverError!,
              action:
                  TextButton(onPressed: _discover, child: const Text('Retry')),
            ),
          )
        else if (!_hasDiscovered)
          Expanded(
            child: _buildEmptyState(
                Icons.travel_explore, 'Tap Discover to find running services.'),
          )
        else if (_services.isEmpty)
          Expanded(
            child: _buildEmptyState(Icons.inbox_outlined,
                'No services responded. This only finds ADR-32 services '
                '(nats.go\'s micro package, etc.) currently running and '
                'reachable on this account.'),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _services.length,
              itemBuilder: (context, index) {
                final service = _services[index];
                final selected = service == _selected;
                return Material(
                  key: ValueKey('${service.name}/${service.id}'),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .inversePrimary
                        .withAlpha(80),
                    title: Text(service.name),
                    subtitle: Text('v${service.version} · ${service.id}'),
                    onTap: () => _selectService(service),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildEndpointRow(String name, String subject,
      EndpointStatsInfo? stats) {
    return ListTile(
      title: Text(name),
      subtitle: Text(
        stats == null
            ? subject
            : '$subject\n${stats.numRequests} req · ${stats.numErrors} err · '
                'avg ${formatNanos(stats.averageProcessingTimeNs)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: stats != null,
    );
  }

  Widget _buildDetailPane() {
    final selected = _selected;
    if (selected == null) {
      return _buildEmptyState(
          Icons.arrow_back, 'Select a service instance to see its details.');
    }

    if (_loadingDetail) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_detailError != null) {
      return _buildEmptyState(
        Icons.error_outline,
        _detailError!,
        action: TextButton(
            onPressed: () => _loadDetail(selected), child: const Text('Retry')),
      );
    }

    final info = _info;
    final stats = _stats;
    final statsByName = {for (final e in stats?.endpoints ?? []) e.name: e};
    final endpoints = info?.endpoints ?? const <EndpointInfo>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${selected.name} (v${selected.version})',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh detail',
              onPressed: () => _loadDetail(selected),
            ),
          ],
        ),
        Text('Instance ${selected.id}',
            style: Theme.of(context).textTheme.bodySmall),
        if (info?.description.isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Text(info!.description),
        ],
        if (stats != null) ...[
          const SizedBox(height: 8),
          Text('Running since ${formatRelativeTime(stats.started.toIso8601String())}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1),
        if (endpoints.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('This service has no registered endpoints.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          )
        else
          ...endpoints.map((e) =>
              _buildEndpointRow(e.name, e.subject, statsByName[e.name])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.manager == null) {
      return _buildEmptyState(
        Icons.cloud_off,
        'Connect to a NATS server to use Service Discovery.',
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 320, child: _buildServiceList()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildDetailPane()),
      ],
    );
  }
}
