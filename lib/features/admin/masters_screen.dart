import 'package:flutter/material.dart';

import '../../core/icon_registry.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
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
          Text('Master Data', style: T.headlineLg),
          const SizedBox(height: 4),
          Text('The lists used when adding software, and domain selling prices.', style: T.bodyMd.copyWith(color: C.secondary)),
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
            numeric: def.fields[i].kind == MasterFieldKind.integer || def.fields[i].kind == MasterFieldKind.decimal,
            sortValue: (r) {
              final v = r[def.fields[i].key];
              return def.fields[i].kind == MasterFieldKind.integer || def.fields[i].kind == MasterFieldKind.decimal ? (v as num?) ?? 0 : '${v ?? ''}'.toLowerCase();
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

  /// Which field gets a "Pick from 20i" button, for the master tables whose values 20i can supply.
  String? get _pickerField => switch (widget.def.table) {
        'hosting_plan_prices' => 'package_type_id',
        'vps_plan_prices' => 'vps_type',
        'ssl_plan_prices' => 'class_code',
        'vps_addon_prices' => 'product_spec',
        'vps_os_options' => 'code',
        _ => null,
      };

  /// VPS add-on prices: choose a cPanel licence, backup or disk from the panel shop's list.
  Future<void> _pickVpsAddon() async {
    try {
      final addons = await vpsCartRepo.panelAddons();
      if (!mounted) return;
      final chosen = await showDialog<({String spec, String label, int months, double price})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('VPS add-ons from 20i'),
          children: [
            if (addons.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing came back from 20i.')),
            for (final a in addons) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, a), child: Text('${a.label}  (${a.spec}, shop price ${a.price.toStringAsFixed(2)} / ${a.months} mo)')),
          ],
        ),
      );
      if (chosen == null) return;
      _text['product_spec']!.text = chosen.spec;
      if (_text['label']!.text.trim().isEmpty) _text['label']!.text = chosen.label;
      if (_text['months']!.text.trim().isEmpty) _text['months']!.text = '${chosen.months}';
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// SSL prices: choose a certificate from the panel shop's list (read through the panel login).
  Future<void> _pickSsl() async {
    try {
      final plans = await sslCartRepo.panelCatalogue();
      if (!mounted) return;
      final chosen = await showDialog<({String code, String label, int months, double price})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('SSL certificates from 20i'),
          children: [
            if (plans.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing came back from 20i.')),
            for (final p in plans) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text('${p.label}  (${p.code}, shop price ${p.price.toStringAsFixed(2)} / ${p.months} mo)')),
          ],
        ),
      );
      if (chosen == null) return;
      _text['class_code']!.text = chosen.code;
      if (_text['plan_name']!.text.trim().isEmpty) _text['plan_name']!.text = chosen.label;
      if (_text['months']!.text.trim().isEmpty) _text['months']!.text = '${chosen.months}';
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// VPS prices / operating systems: choose from the panel shop's list (read through the panel login).
  Future<void> _pickVps() async {
    try {
      final cat = await vpsCartRepo.panelCatalogue();
      if (!mounted) return;
      final isPlan = widget.def.table == 'vps_plan_prices';
      final options = isPlan
          ? [for (final p in cat.plans) (code: p.code, label: p.label, hint: 'shop price ${p.price.toStringAsFixed(2)} / ${p.months} mo', months: p.months)]
          : [for (final o in cat.os) (code: o.code, label: o.label, hint: o.paid ? 'paid' : 'free', months: 0)];
      final chosen = await showDialog<({String code, String label, String hint, int months})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(isPlan ? 'VPS plans from 20i' : 'Operating systems from 20i'),
          children: [
            if (options.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing came back from 20i.')),
            for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o), child: Text('${o.label}  (${o.code}, ${o.hint})')),
          ],
        ),
      );
      if (chosen == null) return;
      if (isPlan) {
        // The shop code vps:a is the 20i type vps-a.
        _text['vps_type']!.text = chosen.code.replaceFirst('vps:', 'vps-');
        if (_text['plan_name']!.text.trim().isEmpty) _text['plan_name']!.text = chosen.label;
        if (_text['months']!.text.trim().isEmpty) _text['months']!.text = '${chosen.months}';
      } else {
        _text['code']!.text = chosen.code;
        if (_text['label']!.text.trim().isEmpty) _text['label']!.text = chosen.label;
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Hosting prices: choose the plan from 20i's own list instead of typing its id.
  Future<void> _pick20iPlan() async {
    try {
      final plans = await hostingCartRepo.plansFrom20i();
      if (!mounted) return;
      final chosen = await showDialog<({String id, String name})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Plans from 20i'),
          children: [
            if (plans.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('20i returned no plans.')),
            for (final p in plans) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text('${p.name}  (${p.id})')),
          ],
        ),
      );
      if (chosen == null) return;
      _text['package_type_id']!.text = chosen.id;
      if (_text['plan_name']!.text.trim().isEmpty) _text['plan_name']!.text = chosen.name;
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
          case MasterFieldKind.decimal:
            values[f.key] = double.tryParse(_text[f.key]!.text.trim()) ?? 0;
          case MasterFieldKind.text when f.key == 'tld':
            values[f.key] = _text[f.key]!.text.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
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
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        TextFormField(
                          controller: _text[f.key],
                          keyboardType: f.kind == MasterFieldKind.integer || f.kind == MasterFieldKind.decimal ? const TextInputType.numberWithOptions(decimal: true) : null,
                          decoration: fieldDecoration(hint: f.hint),
                          validator: f.required ? (v) => (v == null || v.trim().isEmpty) ? '${f.label} is required' : null : null,
                        ),
                        if (f.key == _pickerField)
                          TextButton.icon(
                            onPressed: switch (def.table) { 'hosting_plan_prices' => _pick20iPlan, 'ssl_plan_prices' => _pickSsl, 'vps_addon_prices' => _pickVpsAddon, _ => _pickVps },
                            icon: const Icon(Icons.cloud_download_outlined, size: 18),
                            label: const Text('Pick from 20i'),
                          ),
                      ]),
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
