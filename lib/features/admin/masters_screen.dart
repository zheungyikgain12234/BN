import 'package:flutter/material.dart';

import '../../core/icon_registry.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/masters.dart';

/// Admin: manage the lists the software form picks from (categories, tags, pricing models, currencies).
class MastersScreen extends StatelessWidget {
  const MastersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: masterDefs.length,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Masters', style: T.headlineLg),
          const SizedBox(height: 4),
          Text('The lists used when adding software.', style: T.bodyMd.copyWith(color: C.secondary)),
          const SizedBox(height: 8),
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final d in masterDefs) Tab(text: d.title)]),
          const SizedBox(height: 12),
          Expanded(child: TabBarView(children: [for (final d in masterDefs) _MasterTab(def: d)])),
        ]),
      ),
    );
  }
}

class _MasterTab extends StatefulWidget {
  const _MasterTab({required this.def});
  final MasterDef def;

  @override
  State<_MasterTab> createState() => _MasterTabState();
}

class _MasterTabState extends State<_MasterTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _rows;
  Object? _error;

  MasterDef get def => widget.def;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await masterRepo.list(def);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _MasterDialog(def: def, row: row));
    if (saved == true) _load();
  }

  /// Deleting a value that apps still use first asks where those apps should go.
  Future<void> _delete(Map<String, dynamic> row) async {
    try {
      final inUse = await masterRepo.usageCount(def, row);
      if (!mounted) return;
      if (inUse == 0) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete ${def.singular}?'),
            content: Text('"${row[def.nameKey]}" is not used by any app and will be removed.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: C.error))),
            ],
          ),
        );
        if (ok != true) return;
        await masterRepo.delete(def, row['id'] as String);
      } else {
        final others = _rows!.where((r) => r['id'] != row['id']).toList();
        final choice = await showDialog<({String? value})>(
          context: context,
          builder: (_) => _ReassignDialog(def: def, row: row, inUse: inUse, others: others),
        );
        if (choice == null) return;
        await masterRepo.reassignAndDelete(def, row, choice.value);
      }
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _cell(MasterField f, Map<String, dynamic> row, bool first) {
    final v = row[f.key];
    final text = v == null || '$v'.isEmpty ? '—' : '$v';
    if (f.kind == MasterFieldKind.icon) {
      return Row(mainAxisSize: MainAxisSize.min, children: [Icon(categoryIcon(v as String?), size: 18, color: C.primary), const SizedBox(width: 8), Text(text)]);
    }
    return Text(text, style: first ? T.labelLg : T.bodyMd);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    return SortableTable<Map<String, dynamic>>(
      rows: _rows!,
      searchHint: 'Search ${def.title.toLowerCase()}',
      emptyLabel: 'No ${def.title.toLowerCase()} yet.',
      searchText: (r) => def.fields.map((f) => '${r[f.key] ?? ''}').join(' '),
      toolbar: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: Text('Add ${def.singular}'))],
      columns: [
        for (var i = 0; i < def.fields.length; i++)
          TableCol<Map<String, dynamic>>(
            label: def.fields[i].label,
            numeric: def.fields[i].kind == MasterFieldKind.integer,
            sortValue: (r) {
              final v = r[def.fields[i].key];
              return def.fields[i].kind == MasterFieldKind.integer ? (v as num?) ?? 0 : '${v ?? ''}'.toLowerCase();
            },
            cell: (r) => _cell(def.fields[i], r, i == 0),
          ),
      ],
      actions: (r) => [
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(r)),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _delete(r)),
      ],
    );
  }
}

class _MasterDialog extends StatefulWidget {
  const _MasterDialog({required this.def, this.row});
  final MasterDef def;
  final Map<String, dynamic>? row;

  @override
  State<_MasterDialog> createState() => _MasterDialogState();
}

class _MasterDialogState extends State<_MasterDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _text = {
    for (final f in widget.def.fields.where((f) => f.kind != MasterFieldKind.icon)) f.key: TextEditingController(text: '${widget.row?[f.key] ?? ''}'),
  };
  late final Map<String, String?> _icon = {
    for (final f in widget.def.fields.where((f) => f.kind == MasterFieldKind.icon))
      f.key: categoryIcons.containsKey(widget.row?[f.key]) ? widget.row![f.key] as String : null,
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{};
      for (final f in widget.def.fields) {
        switch (f.kind) {
          case MasterFieldKind.icon:
            values[f.key] = _icon[f.key];
          case MasterFieldKind.integer:
            values[f.key] = int.tryParse(_text[f.key]!.text.trim()) ?? 0;
          case MasterFieldKind.text:
            final t = _text[f.key]!.text.trim();
            values[f.key] = t.isEmpty ? null : t;
        }
      }
      await masterRepo.save(widget.def, values, id: widget.row?['id'] as String?);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e.toString().contains('duplicate key') ? 'This ${widget.def.singular} already exists.' : e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    return AlertDialog(
      title: Text(widget.row == null ? 'Add ${def.singular}' : 'Edit ${def.singular}'),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final f in def.fields) ...[
              LabeledField(
                label: f.label,
                required: f.required,
                child: f.kind == MasterFieldKind.icon
                    ? DropdownButtonFormField<String?>(
                        initialValue: _icon[f.key],
                        isExpanded: true,
                        decoration: fieldDecoration(),
                        hint: dropdownHint(f.hint),
                        items: [
                          for (final e in categoryIcons.entries)
                            DropdownMenuItem<String?>(value: e.key, child: Row(children: [Icon(e.value, size: 18), const SizedBox(width: 10), Text(e.key)])),
                        ],
                        onChanged: (v) => setState(() => _icon[f.key] = v),
                      )
                    : TextFormField(
                        controller: _text[f.key],
                        keyboardType: f.kind == MasterFieldKind.integer ? TextInputType.number : null,
                        decoration: fieldDecoration(hint: f.hint),
                        validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? '${f.label} is required' : null : null,
                      ),
              ),
              const SizedBox(height: 14),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
      ],
    );
  }
}

/// Asks what to do with the apps that use a master value that is about to be deleted.
class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.def, required this.row, required this.inUse, required this.others});
  final MasterDef def;
  final Map<String, dynamic> row;
  final int inUse;
  final List<Map<String, dynamic>> others;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  String? _replacement; // null = clear it on the apps

  String _label(Map<String, dynamic> r) => def.fields.take(2).map((f) => f.kind == MasterFieldKind.icon ? '' : '${r[f.key] ?? ''}').where((s) => s.isNotEmpty).join(' – ');

  MasterDef get def => widget.def;

  @override
  Widget build(BuildContext context) {
    final name = '${widget.row[def.nameKey]}';
    final apps = widget.inUse == 1 ? '1 app uses' : '${widget.inUse} apps use';
    final isTag = def.usageKind == 'tag';
    return AlertDialog(
      title: Text('Reassign before deleting'),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$apps the ${def.singular} "$name". Choose what they should use instead, then it will be deleted.', style: T.bodyMd),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Move these apps to',
            child: DropdownButtonFormField<String?>(
              initialValue: _replacement,
              isExpanded: true,
              decoration: fieldDecoration(),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(isTag ? 'Just remove the tag' : 'None (leave it empty)')),
                for (final r in widget.others) DropdownMenuItem<String?>(value: '${r[def.valueKey]}', child: Text(_label(r), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _replacement = v),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: C.error),
          onPressed: () => Navigator.pop(context, (value: _replacement)),
          child: const Text('Reassign & delete'),
        ),
      ],
    );
  }
}
