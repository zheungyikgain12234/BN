import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icon_registry.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/masters.dart';

/// Admin: manage the lists the software form picks from (categories, tags, pricing models).
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

bool _isNumber(MasterField f) => f.kind == MasterFieldKind.integer || f.kind == MasterFieldKind.decimal || f.kind == MasterFieldKind.money || f.kind == MasterFieldKind.percent;

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
    if (_isDomain) _checkPanel();
  }

  bool _refreshing = false;

  /// Domain prices only: proof of who is logged in (the app user and the panel account that reads the 20i prices).
  String _debug = 'Debug: checking the 20i panel login...';

  Future<void> _checkPanel() async {
    try {
      final p = await domainCartRepo.panelDomains();
      if (mounted) setState(() => _debug = 'Debug: signed in to the app as ${p.appUser} (super admin)  ·  20i panel login OK as ${p.panelUser}  ·  ${p.tlds.length} TLDs read: ${p.tlds.map((t) => '.${t.tld}').join(' ')}');
    } catch (e) {
      if (mounted) setState(() => _debug = 'Debug: 20i panel login FAILED: $e');
    }
  }

  bool get _isDomain => def.table == 'domain_tld_prices';


  /// Copies 20i's current yearly cost onto every TLD in the table, so selling prices follow 20i's price changes.
  Future<void> _refreshCosts() async {
    setState(() => _refreshing = true);
    try {
      final n = await withLoader(context, () => masterRepo.refreshCosts(def, _rows ?? const []), message: 'Updating costs from 20i...');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Costs are already up to date.' : '$n cost(s) updated from 20i.'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
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
    final saved = await showDialog<bool>(context: context, builder: (_) => _MasterDialog(def: def, row: row, existingTlds: {for (final r in _rows ?? const <Map<String, dynamic>>[]) '${r['tld'] ?? r['code']}'}));
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
    final text = v == null || '$v'.isEmpty ? '—' : f.kind == MasterFieldKind.money ? money((v as num).toDouble()) : f.kind == MasterFieldKind.percent ? '$v%' : '$v';
    if (f.kind == MasterFieldKind.icon) {
      return Row(mainAxisSize: MainAxisSize.min, children: [Icon(categoryIcon(v as String?), size: 18, color: C.primary), const SizedBox(width: 8), Text(text)]);
    }
    if (f.kind == MasterFieldKind.tld) return Text('.$text', style: T.labelLg);
    return Text(text, style: first ? T.labelLg : T.bodyMd);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    final table = SortableTable<Map<String, dynamic>>(
      rows: _rows!,
      searchHint: 'Search ${def.title.toLowerCase()}',
      emptyLabel: 'No ${def.title.toLowerCase()} yet.',
      searchText: (r) => def.fields.map((f) => '${r[f.key] ?? ''}').join(' '),
      toolbar: [
        FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: Text('Add ${def.singular}')),
        if (MasterRepository.hasCost(def)) OutlinedButton.icon(onPressed: _refreshing ? null : _refreshCosts, icon: const Icon(Icons.sync, size: 18), label: Text(_refreshing ? 'Updating...' : 'Update costs from 20i')),
      ],
      columns: [
        for (var i = 0; i < def.fields.length; i++)
          TableCol<Map<String, dynamic>>(
            label: def.fields[i].label,
            numeric: _isNumber(def.fields[i]),
            sortValue: (r) {
              final v = r[def.fields[i].key];
              return _isNumber(def.fields[i]) ? (v as num?) ?? -1 : '${v ?? ''}'.toLowerCase();
            },
            cell: (r) => _cell(def.fields[i], r, i == 0),
          ),
      ],
      actions: (r) => [
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(r)),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _delete(r)),
      ],
    );
    if (!_isDomain) return table;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SelectableText(_debug, style: T.bodySm.copyWith(color: _debug.contains('FAILED') ? C.error : C.tertiary)),
      const SizedBox(height: 12),
      Expanded(child: table),
    ]);
  }
}

class _MasterDialog extends StatefulWidget {
  const _MasterDialog({required this.def, this.row, this.existingTlds = const {}});
  final MasterDef def;
  final Map<String, dynamic>? row;

  /// Extensions that already have a price (they are not offered again when adding).
  final Set<String> existingTlds;

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

  /// Domain prices: 20i's yearly cost for the extension picked (the cost column is never typed).
  double? _cost;
  ({int? cores, int? ramMb, int? diskGb})? _specs; // VPS plan specs from 20i, set when a plan is picked

  /// Domain prices: choose the extension from 20i's own list, with a search box.
  Future<void> _pickTld() async {
    try {
      final all = await withLoader(context, domainCartRepo.tldsFrom20i, message: 'Loading extensions from 20i...');
      if (!mounted) return;
      final options = all.where((t) => !widget.existingTlds.contains(t.tld)).toList();
      final chosen = await showDialog<({String tld, double? cost})>(context: context, builder: (_) => _TldPickerDialog(options: options));
      if (chosen == null) return;
      setState(() {
        _text['tld']!.text = chosen.tld;
        _cost = chosen.cost;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// VPS plans / add-ons: choose from 20i's own list (the plan, its billing period and 20i's cost come with it).
  Future<void> _pickPanel() => switch (widget.def.table) {
        'vps_plan_prices' => _pickVps(),
        'hosting_plan_prices' => _pickHosting(),
        'ssl_plan_prices' => _pickSsl(),
        'vps_locations' => _pickLocation(),
        _ => _pickVpsAddon(),
      };

  /// VPS locations: choose a data centre from the ones 20i's panel offers.
  Future<void> _pickLocation() async {
    try {
      final all = await withLoader(context, vpsCartRepo.panelLocations, message: 'Loading locations from 20i...');
      if (!mounted) return;
      final options = all.where((l) => !widget.existingTlds.contains(l.code)).toList();
      final chosen = await showDialog<({String code, String label})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Locations from 20i'),
          children: [
            if (options.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No more locations to add (or 20i returned none).')),
            for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o), child: Text('${o.label}  (${o.code})')),
          ],
        ),
      );
      if (chosen == null) return;
      setState(() {
        _text['code']!.text = chosen.code;
        _text['label']!.text = chosen.label;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Which field gets a "Pick from 20i" button, for the master tables whose values 20i can supply.
  String? get _pickerField => switch (widget.def.table) {
        'vps_os_options' => 'code',
        _ => null,
      };

  /// VPS add-on prices: choose a cPanel licence, backup or disk from the panel shop's list.
  Future<void> _pickVpsAddon() async {
    try {
      final addons = await withLoader(context, vpsCartRepo.panelAddons);
      if (!mounted) return;
      final chosen = await showDialog<({String spec, String label, int months, double price})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('VPS add-ons from 20i (cost per period)'),
          children: [
            if (addons.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing came back from 20i.')),
            for (final a in addons) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, a), child: Text('${a.label}  ·  ${a.months} ${a.months == 1 ? 'month' : 'months'}  ·  cost ${money(a.price)}')),
          ],
        ),
      );
      if (chosen == null) return;
      setState(() {
        _text['product_spec']!.text = chosen.spec;
        _text['label']!.text = chosen.label;
        _text['months']!.text = '${chosen.months}';
        _cost = chosen.price;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// SSL prices: choose a certificate and billing period from the panel shop's list (the class code and 20i's cost come with it).
  Future<void> _pickSsl() async {
    try {
      final plans = await withLoader(context, sslCartRepo.panelCatalogue, message: 'Loading certificates from 20i...');
      if (!mounted) return;
      final chosen = await showDialog<({String code, String label, int months, double price})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('SSL certificates from 20i (cost per period)'),
          children: [
            if (plans.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing came back from 20i.')),
            for (final p in plans) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text('${p.label}  ·  ${p.months} ${p.months == 1 ? 'month' : 'months'}  ·  cost ${money(p.price)}  (${p.code})')),
          ],
        ),
      );
      if (chosen == null) return;
      setState(() {
        _text['class_code']!.text = chosen.code;
        _text['plan_name']!.text = chosen.label;
        _text['months']!.text = '${chosen.months}';
        _cost = chosen.price;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// VPS prices / operating systems: choose from the panel shop's list (read through the panel login).
  Future<void> _pickVps() async {
    try {
      final cat = await withLoader(context, vpsCartRepo.panelCatalogue);
      if (!mounted) return;
      final isPlan = widget.def.table == 'vps_plan_prices';
      final options = isPlan
          ? [for (final p in cat.plans) (code: p.code, label: p.label, hint: '${p.months} ${p.months == 1 ? 'month' : 'months'} · cost ${money(p.price)}', months: p.months, cost: p.price, cores: p.cores, ramMb: p.ramMb, diskGb: p.diskGb)]
          : [for (final o in cat.os) (code: o.code, label: o.label, hint: o.paid ? 'paid' : 'free', months: 0, cost: 0.0, cores: null as int?, ramMb: null as int?, diskGb: null as int?)];
      final chosen = await showDialog<({String code, String label, String hint, int months, double cost, int? cores, int? ramMb, int? diskGb})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(isPlan ? 'VPS plans from 20i (cost per period)' : 'Operating systems from 20i'),
          children: [
            if (options.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing came back from 20i.')),
            for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o), child: Text(isPlan ? '${o.label}  ·  ${o.hint}' : '${o.label}  (${o.code}, ${o.hint})')),
          ],
        ),
      );
      if (chosen == null) return;
      if (isPlan) {
        // The shop code vps:a is the 20i type vps-a.
        setState(() {
          _text['vps_type']!.text = chosen.code.replaceFirst('vps:', 'vps-');
          _text['plan_name']!.text = chosen.label;
          _text['months']!.text = '${chosen.months}';
          _cost = chosen.cost;
          _specs = (cores: chosen.cores, ramMb: chosen.ramMb, diskGb: chosen.diskGb);
        });
      } else {
        _text['code']!.text = chosen.code;
        if (_text['label']!.text.trim().isEmpty) _text['label']!.text = chosen.label;
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Hosting prices: choose the plan and billing period from the 20i shop (the plan id and 20i's cost come with it).
  Future<void> _pickHosting() async {
    try {
      final plans = await withLoader(context, hostingCartRepo.panelHosting, message: 'Loading hosting plans from 20i...');
      if (!mounted) return;
      final chosen = await showDialog<({String code, String typeId, String label, int months, double price})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Hosting plans from 20i (cost per period)'),
          children: [
            for (final p in plans)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: Text('${p.label}  ·  ${p.months} ${p.months == 1 ? 'month' : 'months'}  ·  cost ${money(p.price)}  (${p.typeId})'),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      setState(() {
        _text['package_type_id']!.text = chosen.typeId;
        _text['plan_name']!.text = chosen.label;
        _text['months']!.text = '${chosen.months}';
        _cost = chosen.price;
      });
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
          case MasterFieldKind.integer when !f.readOnly:
            values[f.key] = int.tryParse(_text[f.key]!.text.trim()) ?? 0;
          case MasterFieldKind.decimal:
            values[f.key] = double.tryParse(_text[f.key]!.text.trim()) ?? 0;
          case MasterFieldKind.money when f.readOnly:
            if ((f.key == 'cost_per_year' || f.key == 'cost') && _cost != null) values[f.key] = _cost; // only changes when something new was picked from 20i
          case MasterFieldKind.integer:
            values[f.key] = int.parse(_text[f.key]!.text.trim()); // filled in by the 20i picker
          case MasterFieldKind.text when f.readOnly:
            values[f.key] = _text[f.key]!.text.trim(); // filled in by the 20i picker
          case MasterFieldKind.panel:
            values[f.key] = _text[f.key]!.text.trim();
          case MasterFieldKind.percent:
            values[f.key] = double.parse(_text[f.key]!.text.trim()); // validated as a number >= 0 by the form
          case MasterFieldKind.money:
            values[f.key] = double.tryParse(_text[f.key]!.text.trim()) ?? 0;
          case MasterFieldKind.tld:
            values[f.key] = _text[f.key]!.text.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
          case MasterFieldKind.text:
            final t = _text[f.key]!.text.trim();
            values[f.key] = t.isEmpty ? null : t;
        }
      }
      if (widget.def.table == 'vps_plan_prices' && _specs != null) {
        values['cpu_cores'] = _specs!.cores;
        values['ram_mb'] = _specs!.ramMb;
        values['disk_gb'] = _specs!.diskGb;
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
            for (final f in def.fields.where((f) => !f.readOnly)) ...[
              LabeledField(
                label: f.label,
                required: f.required,
                child: (f.kind == MasterFieldKind.tld || f.kind == MasterFieldKind.panel)
                    ? FormField<String>(
                        initialValue: _text[f.key]!.text,
                        validator: (_) => _text[f.key]!.text.isEmpty ? '${f.label} is required' : null,
                        builder: (state) {
                          final tld = _text[f.key]!.text;
                          final panel = f.kind == MasterFieldKind.panel;
                          final shown = !panel ? '.$tld' : (def.table == 'vps_plan_prices' || def.table == 'hosting_plan_prices' || def.table == 'ssl_plan_prices') ? '${_text['plan_name']!.text}  ·  ${_text['months']!.text} mo' : def.table == 'vps_locations' ? '${_text['label']!.text}  (${_text['code']!.text})' : '${_text['label']!.text}  ·  ${_text['months']!.text} mo';
                          // An existing price keeps its extension; a new one is picked from 20i's list.
                          final locked = widget.row != null;
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            InkWell(
                              onTap: locked ? null : (panel ? _pickPanel : _pickTld),
                              child: InputDecorator(
                                decoration: fieldDecoration().copyWith(errorText: state.errorText, suffixIcon: locked ? null : const Icon(Icons.arrow_drop_down)),
                                child: tld.isEmpty ? dropdownHint(f.hint) : Text(shown, style: T.bodyMd),
                              ),
                            ),
                            if (_cost != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('20i cost: ${money(_cost!)} per ${panel ? 'period' : 'year'}', style: T.bodySm.copyWith(color: C.secondary))),
                          ]);
                        },
                      )
                    : f.kind == MasterFieldKind.icon
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
                          keyboardType: _isNumber(f) ? const TextInputType.numberWithOptions(decimal: true) : null,
                          decoration: fieldDecoration(hint: f.hint).copyWith(prefixText: f.kind == MasterFieldKind.money ? '$kCurrency ' : null, suffixText: f.kind == MasterFieldKind.percent ? '%' : null),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return f.required ? '${f.label} is required' : null;
                            if (f.kind == MasterFieldKind.percent) {
                              final n = double.tryParse(t);
                              if (n == null || n < 0) return 'Enter a number, 0 or more';
                            }
                            return null;
                          },
                        ),
                        if (f.key == _pickerField)
                          TextButton.icon(
                            onPressed: _pickVps,
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

/// Searchable list of the extensions 20i offers; pops the one tapped.
class _TldPickerDialog extends StatefulWidget {
  const _TldPickerDialog({required this.options});
  final List<({String tld, double? cost})> options;

  @override
  State<_TldPickerDialog> createState() => _TldPickerDialogState();
}

class _TldPickerDialogState extends State<_TldPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    final shown = widget.options.where((t) => t.tld.contains(q)).toList();
    return AlertDialog(
      title: const Text('Select a TLD'),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            autofocus: true,
            decoration: fieldDecoration(hint: 'Search, e.g. com or uk', prefix: Icons.search),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(widget.options.isEmpty ? 'No more extensions to add.' : 'No match.', style: T.bodyMd))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text('.${shown[i].tld}'),
                      trailing: shown[i].cost == null ? null : Text('${money(shown[i].cost!)} / yr', style: T.bodySm.copyWith(color: C.secondary)),
                      onTap: () => Navigator.pop(context, shown[i]),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
