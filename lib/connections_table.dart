import 'package:flutter/material.dart';

import 'format_utils.dart';
import 'jetstream_manager.dart' show formatBytes;
import 'server_monitor.dart';

/// Rows-per-page choices for the connections list. The Docker relay caps
/// `limit` at 100, so stay at or under that.
const List<int> connzPageSizes = [10, 25, 50];

/// Column headings for the [ConnzSort] orders, as the table shows them.
String connzSortLabel(ConnzSort sort) => switch (sort) {
      ConnzSort.cid => 'CID',
      ConnzSort.subs => 'Subs',
      ConnzSort.pending => 'Pending',
      ConnzSort.msgsFrom => 'Msgs in',
      ConnzSort.msgsTo => 'Msgs out',
      ConnzSort.uptime => 'Uptime',
    };

/// One page of `/connz`, with server-side sorting and paging: there's no
/// sorting or filtering here, because this page is all the app has.
///
/// [narrow] swaps the table for a list of rows that expand to show the
/// address, client and uptime, and a sort dropdown for the headers.
class ConnectionsTable extends StatelessWidget {
  const ConnectionsTable({
    super.key,
    required this.page,
    required this.sort,
    required this.offset,
    required this.limit,
    required this.narrow,
    required this.onSort,
    required this.onOffset,
    required this.onLimit,
  });

  final ConnzPage? page;
  final ConnzSort sort;
  final int offset;
  final int limit;
  final bool narrow;
  final ValueChanged<ConnzSort> onSort;
  final ValueChanged<int> onOffset;
  final ValueChanged<int> onLimit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = this.page;
    // Title and page controls share the top row, so paging never means
    // scrolling past a page of rows first.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Text('Connections',
                  key: const ValueKey('connectionsHeading'),
                  style: theme.textTheme.titleSmall),
              _pager(context, page),
            ],
          ),
        ),
        if (narrow) _sortPicker(context),
        if (page == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (page.connections.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No open connections.')),
          )
        else if (narrow)
          _list(context, page)
        else
          _table(context, page),
        if (!narrow)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Text(
              '/connz?sort=${sort.apiValue}&offset=$offset&limit=$limit',
              style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _sortPicker(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          const Text('Sort by'),
          const SizedBox(width: 12),
          DropdownButton<ConnzSort>(
            key: const ValueKey('connzSortPicker'),
            value: sort,
            isDense: true,
            items: [
              for (final s in ConnzSort.values)
                DropdownMenuItem(value: s, child: Text(connzSortLabel(s))),
            ],
            onChanged: (s) {
              if (s != null) onSort(s);
            },
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, ConnzPage page) {
    final mono = TextStyle(
        fontFamily: 'monospace',
        fontSize: Theme.of(context).textTheme.bodySmall?.fontSize);
    // The server picks the direction for each sort, so the arrow just shows
    // it; tapping the sorted column again does nothing new.
    DataColumn sortable(ConnzSort s) => DataColumn(
          label: Text(connzSortLabel(s)),
          numeric: s != ConnzSort.cid,
          onSort: (_, __) => onSort(s),
        );
    const columns = <Object>[
      ConnzSort.cid,
      'Name',
      'Address',
      'Client',
      ConnzSort.subs,
      ConnzSort.pending,
      ConnzSort.msgsFrom,
      ConnzSort.msgsTo,
      ConnzSort.uptime,
    ];
    // At least as wide as the card, and scrolls sideways only when the
    // columns need more room than that.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: _dataTable(context, page, columns, sortable, mono),
        ),
      ),
    );
  }

  Widget _dataTable(BuildContext context, ConnzPage page, List<Object> columns,
      DataColumn Function(ConnzSort) sortable, TextStyle mono) {
    return DataTable(
      sortColumnIndex: columns.indexOf(sort),
      sortAscending: sort.ascending,
      headingRowHeight: 40,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 40,
      columnSpacing: 16,
      horizontalMargin: 16,
      columns: [
        for (final c in columns)
          c is ConnzSort ? sortable(c) : DataColumn(label: Text(c as String)),
      ],
      rows: [
        for (final c in page.connections)
          DataRow(cells: [
            DataCell(Text('${c.cid}', style: mono)),
            DataCell(Text(c.name.isEmpty ? '—' : c.name)),
            DataCell(Text(c.address, style: mono)),
            DataCell(Text(c.client)),
            DataCell(Text(formatGroupedCount(c.subscriptions))),
            DataCell(Text(formatBytes(c.pendingBytes))),
            DataCell(Text(formatGroupedCount(c.inMsgs))),
            DataCell(Text(formatGroupedCount(c.outMsgs))),
            DataCell(Text(
                c.uptime == null ? '—' : formatConfiguredDuration(c.uptime!))),
          ]),
      ],
    );
  }

  Widget _list(BuildContext context, ConnzPage page) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      children: [
        for (final c in page.connections)
          ExpansionTile(
            key: ValueKey('conn-${c.cid}'),
            dense: true,
            title: Text(c.name.isEmpty ? 'CID ${c.cid}' : c.name),
            subtitle: Text(
              'CID ${c.cid} · ${formatGroupedCount(c.subscriptions)} subs · '
              'in ${formatGroupedCount(c.inMsgs)} · '
              'out ${formatGroupedCount(c.outMsgs)}',
              style: small,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Text(
                [
                  c.address,
                  if (c.client.isNotEmpty) c.client,
                  if (c.uptime != null)
                    'up ${formatConfiguredDuration(c.uptime!)}',
                  'pending ${formatBytes(c.pendingBytes)}',
                ].join(' · '),
                style: small,
              ),
            ],
          ),
      ],
    );
  }

  Widget _pager(BuildContext context, ConnzPage? page) {
    final total = page?.total ?? 0;
    final shown = page?.connections.length ?? 0;
    final range = total == 0
        ? '0 of 0'
        : '${formatGroupedCount(offset + 1)}–'
            '${formatGroupedCount(offset + shown)} of '
            '${formatGroupedCount(total)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Rows'),
        const SizedBox(width: 8),
        DropdownButton<int>(
          key: const ValueKey('connzPageSize'),
          value: limit,
          isDense: true,
          items: [
            for (final n in connzPageSizes)
              DropdownMenuItem(value: n, child: Text('$n')),
          ],
          onChanged: (n) {
            if (n != null) onLimit(n);
          },
        ),
        const SizedBox(width: 12),
        Text(range),
        IconButton(
          tooltip: 'Previous page',
          icon: const Icon(Icons.chevron_left),
          onPressed: offset == 0
              ? null
              : () => onOffset((offset - limit).clamp(0, offset)),
        ),
        IconButton(
          tooltip: 'Next page',
          icon: const Icon(Icons.chevron_right),
          onPressed:
              offset + shown >= total ? null : () => onOffset(offset + limit),
        ),
      ],
    );
  }
}
