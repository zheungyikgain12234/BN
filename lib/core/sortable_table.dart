import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// One column of a [SortableTable]. Columns with a [sortValue] can be sorted.
class TableCol<R> {
  const TableCol({required this.label, required this.cell, this.sortValue, this.numeric = false});
  final String label;
  final Widget Function(R row) cell;
  final Comparable<Object?> Function(R row)? sortValue;
  final bool numeric;
}

/// Searchable, sortable table with row actions. On narrow screens it turns into a list of cards
/// with a sort picker, so every management screen is usable on a phone.
class SortableTable<R> extends StatefulWidget {
  const SortableTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.searchText,
    this.actions,
    this.emptyLabel = 'Nothing here yet.',
    this.searchHint = 'Search',
    this.toolbar = const [],
    this.footer,
  });

  final List<R> rows;
  final List<TableCol<R>> columns;

  /// Text a row is matched against when the user types in the search box.
  final String Function(R row) searchText;
  final List<Widget> Function(R row)? actions;
  final String emptyLabel;
  final String searchHint;

  /// Extra controls shown next to the search box (e.g. an "Add" button).
  final List<Widget> toolbar;
  final Widget? footer;

  @override
  State<SortableTable<R>> createState() => _SortableTableState<R>();
}

class _SortableTableState<R> extends State<SortableTable<R>> {
  static const _narrow = 720.0;

  final _search = TextEditingController();
  int? _sortCol;
  bool _asc = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<R> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty ? [...widget.rows] : widget.rows.where((r) => widget.searchText(r).toLowerCase().contains(q)).toList();
    final i = _sortCol;
    if (i != null && i < widget.columns.length) {
      final value = widget.columns[i].sortValue;
      if (value != null) {
        list.sort((a, b) {
          final c = Comparable.compare(value(a), value(b));
          return _asc ? c : -c;
        });
      }
    }
    return list;
  }

  void _clear() => setState(() {
        _search.clear();
        _sortCol = null;
        _asc = true;
      });

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final filtered = _search.text.isNotEmpty || _sortCol != null;
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < _narrow;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _toolbar(narrow, filtered),
        const SizedBox(height: 12),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(widget.rows.isEmpty ? widget.emptyLabel : 'No results match your search.', style: T.bodyMd.copyWith(color: C.secondary)))
              : narrow
                  ? _cards(rows)
                  : _table(rows, c.maxWidth),
        ),
        if (widget.footer != null) ...[const SizedBox(height: 12), widget.footer!],
      ]);
    });
  }

  Widget _toolbar(bool narrow, bool filtered) {
    final search = SizedBox(
      height: 40,
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: T.bodyMd,
        decoration: fieldDecoration(hint: widget.searchHint, prefix: Icons.search).copyWith(contentPadding: EdgeInsets.zero),
      ),
    );
    final sortable = [for (var i = 0; i < widget.columns.length; i++) if (widget.columns[i].sortValue != null) i];
    final sortPicker = narrow && sortable.isNotEmpty
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<int>(
              value: _sortCol,
              hint: const Text('Sort by'),
              underline: const SizedBox.shrink(),
              items: [for (final i in sortable) DropdownMenuItem(value: i, child: Text(widget.columns[i].label))],
              onChanged: (v) => setState(() => _sortCol = v),
            ),
            IconButton(
              tooltip: _asc ? 'Ascending' : 'Descending',
              icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
              onPressed: () => setState(() => _asc = !_asc),
            ),
          ])
        : null;
    final clear = filtered ? TextButton.icon(onPressed: _clear, icon: const Icon(Icons.filter_alt_off_outlined, size: 18), label: const Text('Clear')) : null;
    return Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(width: narrow ? double.infinity : 320, child: search),
      ?sortPicker,
      ?clear,
      ...widget.toolbar,
    ]);
  }

  Widget _table(List<R> rows, double width) {
    final hasActions = widget.actions != null;
    return Container(
      decoration: BoxDecoration(
        color: C.surfaceLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width - 2),
            child: DataTable(
              sortColumnIndex: _sortCol,
              sortAscending: _asc,
              headingRowColor: WidgetStatePropertyAll(C.surfaceContainer),
              headingTextStyle: T.labelMd,
              headingRowHeight: 40,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columnSpacing: 20,
              columns: [
                for (var i = 0; i < widget.columns.length; i++)
                  DataColumn(
                    label: Text(widget.columns[i].label),
                    numeric: widget.columns[i].numeric,
                    onSort: widget.columns[i].sortValue == null
                        ? null
                        : (col, asc) => setState(() {
                              _sortCol = col;
                              _asc = asc;
                            }),
                  ),
                if (hasActions) const DataColumn(label: Text('')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    for (final col in widget.columns) DataCell(col.cell(r)),
                    if (hasActions) DataCell(Row(mainAxisSize: MainAxisSize.min, children: widget.actions!(r))),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cards(List<R> rows) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = rows[i];
        final cols = widget.columns;
        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: cols.first.cell(r)),
              if (widget.actions != null) Row(mainAxisSize: MainAxisSize.min, children: widget.actions!(r)),
            ]),
            for (final col in cols.skip(1)) ...[
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 96, child: Text(col.label, style: T.labelSm.copyWith(color: C.secondary))),
                Expanded(child: col.cell(r)),
              ]),
            ],
          ]),
        );
      },
    );
  }
}
