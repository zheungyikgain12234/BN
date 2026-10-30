import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icon_registry.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/masters.dart';
import '../hosting/hosting_screen.dart';
import '../ssl/ssl_screen.dart';

/// What is inside a hosting package (limits and tick/cross features), in its own window.
Future<void> _showPackageDetails(BuildContext context, String title, Map<String, dynamic> limits) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(title, style: T.headlineSm),
              trailing: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: HostingPackageDetails(limits: limits))),
          ]),
        ),
      ),
    );

/// Admin: manage one master list (chosen by its table name in the address), one page per list.
class MastersScreen extends StatelessWidget {
  const MastersScreen({super.key, required this.table});
  final String table;

  @override
  Widget build(BuildContext context) {
    final def = masterDefs.where((d) => d.table == table).firstOrNull;
    if (def == null) return const Center(child: Text('Unknown list.'));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(def.menu, style: T.headlineLg),
        const SizedBox(height: 12),
        Expanded(child: _MasterTab(key: ValueKey(def.table), def: def)),
      ]),
    );
  }
}

bool _isNumber(MasterField f) => f.kind == MasterFieldKind.integer || f.kind == MasterFieldKind.decimal || f.kind == MasterFieldKind.money || f.kind == MasterFieldKind.percent;

class _MasterTab extends StatefulWidget {
  const _MasterTab({super.key, required this.def});
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
  String _debug = 'Debug: checking the panel login...';

  Future<void> _checkPanel() async {
    try {
      final p = await domainCartRepo.panelDomains();
      if (mounted) setState(() => _debug = 'Debug: signed in to the app as ${p.appUser} (super admin)  ·  panel login OK as ${p.panelUser}  ·  ${p.tlds.length} TLDs read: ${p.tlds.map((t) => '.${t.tld}').join(' ')}');
    } catch (e) {
      if (mounted) setState(() => _debug = 'Debug: panel login FAILED: $e');
    }
  }

  bool get _isDomain => def.table == 'domain_tld_prices';


  /// Copies 20i's current yearly cost onto every TLD in the table, so selling prices follow 20i's price changes.
  Future<void> _refreshCosts() async {
    setState(() => _refreshing = true);
    try {
      final n = await withLoader(context, () => masterRepo.refreshCosts(def, _rows ?? const []), message: 'Updating market prices...');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Market prices are already up to date.' : '$n market price(s) updated.'), behavior: SnackBarBehavior.floating));
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
    final saved = await showDialog<bool>(context: context, builder: (_) => _MasterDialog(def: def, row: row, existingTlds: {for (final r in _rows ?? const <Map<String, dynamic>>[]) '${r['tld'] ?? r['code'] ?? r['vps_type'] ?? r['product_spec']}'}));
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
        if (MasterRepository.hasCost(def)) OutlinedButton.icon(onPressed: _refreshing ? null : _refreshCosts, icon: const Icon(Icons.sync, size: 18), label: Text(_refreshing ? 'Updating...' : 'Update market price')),
      ],
      columns: [
        for (var i = 0; i < def.fields.length; i++)
          if (def.fields[i].inTable)
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
        if (def.table == 'hosting_plan_prices')
          IconButton(
            tooltip: 'View what is inside this package',
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => _showPackageDetails(context, '${r['plan_name']}', Map<String, dynamic>.from((r['limits'] as Map?) ?? const {})),
          ),
        if (def.table == 'ssl_plan_prices')
          IconButton(
            tooltip: 'View what is included in this certificate',
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => _showSslDetails(context, '${r['plan_name']}', '${r['class_code']}', features: [for (final f in (r['features'] as List? ?? const [])) '$f'], summary: '${r['summary'] ?? ''}'),
          ),
        if (def.table == 'vps_plan_prices')
          IconButton(
            tooltip: 'View what is inside this VPS',
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => _showVpsDetails(context, '${r['plan_name']}', cores: r['cpu_cores'] as int?, ramMb: r['ram_mb'] as int?, diskGb: r['disk_gb'] as int?),
          ),
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
  List<String>? _features; // hosting plan contents from 20i, set when a plan is picked
  Map<String, dynamic>? _limits; // hosting plan full limits and feature flags from 20i
  List<String>? _sslFeatures; // what the SSL certificate includes, from 20i's order page, set when one is picked
  String _sslSummary = '';

  /// Domain prices: choose the extension from 20i's own list, with a search box.
  Future<void> _pickTld() async {
    try {
      final all = await withLoader(context, domainCartRepo.tldsFrom20i, message: 'Loading extensions...');
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
      final all = await withLoader(context, vpsCartRepo.panelLocations, message: 'Loading locations...');
      if (!mounted) return;
      final options = all.where((l) => !widget.existingTlds.contains(l.code)).toList();
      final chosen = await showDialog<({String code, String label})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Locations'),
          children: [
            if (options.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No more locations to add.')),
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

  /// VPS add-ons: choose a cPanel licence, backup or disk from the panel shop's list.
  Future<void> _pickVpsAddon() async {
    try {
      final addons = await withLoader(context, vpsCartRepo.panelAddons);
      if (!mounted) return;
      final options = addons.where((a) => !widget.existingTlds.contains(a.spec)).toList();
      final chosen = await showDialog<({String spec, String label, double costPerMonth})>(
        context: context,
        builder: (_) => _PickerDialog(
          title: 'VPS add-ons',
          emptyText: 'No more add-ons to add.',
          items: [for (final a in options) _PickerItem(value: a, title: a.label, subtitle: 'Add-on ID ${a.spec}', price: 'Market price: ${money(a.costPerMonth)} per month')],
        ),
      );
      if (chosen == null) return;
      setState(() {
        _text['product_spec']!.text = chosen.spec;
        _text['label']!.text = chosen.label;
        _cost = chosen.costPerMonth;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// SSL: choose a certificate and billing period from the panel shop's list (the class code and market price come with it).
  Future<void> _pickSsl() async {
    try {
      final all = await withLoader(context, sslCartRepo.panelCatalogue, message: 'Loading certificates...');
      if (!mounted) return;
      // SSL is sold per year: one entry per certificate, priced as a year (from its shortest billing period).
      final byCode = <String, ({String code, String label, int months, double price, List<String> features, String summary})>{};
      for (final p in all) {
        final old = byCode[p.code];
        if (old != null && old.months <= p.months) continue;
        byCode[p.code] = (code: p.code, label: p.label, months: p.months, price: p.price, features: p.features, summary: p.summary);
      }
      final plans = [
        for (final p in byCode.values) (code: p.code, label: p.label, months: 12, price: (p.price / p.months * 12 * 100).round() / 100, features: p.features, summary: p.summary),
      ];
      final chosen = await showDialog<({String code, String label, int months, double price, List<String> features, String summary})>(
        context: context,
        builder: (_) => _PickerDialog(
          title: 'SSL certificates',
          emptyText: 'Nothing to show.',
          items: [
            for (final p in plans)
              _PickerItem(
                value: p,
                title: p.label,
                subtitle: 'Billed every year  ·  Certificate ID ${p.code}',
                price: 'Market price: ${money(p.price)} per year',
                onInfo: (ctx) => _showSslDetails(ctx, p.label, p.code, features: p.features, summary: p.summary),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      setState(() {
        _text['class_code']!.text = chosen.code;
        _text['plan_name']!.text = chosen.label;
        _text['months']!.text = '${chosen.months}';
        _cost = chosen.price;
        _sslFeatures = chosen.features;
        _sslSummary = chosen.summary;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// VPS plans / operating systems: choose from the panel shop's list (read through the panel login).
  Future<void> _pickVps() async {
    try {
      final cat = await withLoader(context, vpsCartRepo.panelCatalogue);
      if (!mounted) return;
      final isPlan = widget.def.table == 'vps_plan_prices';
      if (!isPlan) {
        final chosen = await showDialog<({String code, String label})>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Operating systems'),
            children: [
              if (cat.os.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to show.')),
              for (final o in cat.os) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, (code: o.code, label: o.label)), child: Text('${o.label}  (${o.code}, ${o.paid ? 'paid' : 'free'})')),
            ],
          ),
        );
        if (chosen == null) return;
        _text['code']!.text = chosen.code;
        if (_text['label']!.text.trim().isEmpty) _text['label']!.text = chosen.label;
        return;
      }
      // Plans already in Master Data are not offered again (one price per plan; the term is chosen when ordering).
      final options = vpsPlansPerMonth(cat.plans).where((p) => !widget.existingTlds.contains(p.code.replaceFirst('vps:', 'vps-'))).toList();
      final chosen = await showDialog<({String code, String label, double costPerMonth, int? cores, int? ramMb, int? diskGb})>(
        context: context,
        builder: (_) => _PickerDialog(
          title: 'VPS plans',
          emptyText: 'No more plans to add.',
          items: [
            for (final p in options)
              _PickerItem(
                value: p,
                title: p.label,
                subtitle: 'Plan ID ${p.code.replaceFirst('vps:', 'vps-')}',
                price: 'Market price: ${money(p.costPerMonth)} per month',
                onInfo: (ctx) => _showVpsDetails(ctx, p.label, cores: p.cores, ramMb: p.ramMb, diskGb: p.diskGb),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      // The shop code vps:a is the type vps-a.
      setState(() {
        _text['vps_type']!.text = chosen.code.replaceFirst('vps:', 'vps-');
        _text['plan_name']!.text = chosen.label;
        _cost = chosen.costPerMonth;
        _specs = (cores: chosen.cores, ramMb: chosen.ramMb, diskGb: chosen.diskGb);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Hosting packages: choose the plan and billing period from the shop (the plan id and market price come with it).
  Future<void> _pickHosting() async {
    try {
      final plans = await withLoader(context, hostingCartRepo.panelHosting, message: 'Loading hosting plans...');
      if (!mounted) return;
      final chosen = await showDialog<({String code, String typeId, String label, int months, double price, List<String> features, Map<String, dynamic> limits})>(
        context: context,
        builder: (_) => _PickerDialog(
          title: 'Hosting packages',
          emptyText: 'Nothing to show.',
          items: [
            for (final p in plans)
              _PickerItem(
                value: p,
                title: p.label,
                subtitle: 'Billed every ${p.months} ${p.months == 1 ? 'month' : 'months'}  ·  Plan ID ${p.typeId}',
                price: 'Market price: ${money(p.price)}',
                onInfo: (ctx) => _showPackageDetails(ctx, p.label, p.limits),
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
        _features = chosen.features;
        _limits = chosen.limits;
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
            if ((f.key == 'cost_per_year' || f.key == 'cost' || f.key == 'cost_per_month') && _cost != null) values[f.key] = _cost; // only changes when something new was picked from 20i
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
      if (widget.def.table == 'hosting_plan_prices' && _features != null) {
        values['features'] = _features;
        values['limits'] = _limits ?? const {};
      }
      if (widget.def.table == 'ssl_plan_prices' && _sslFeatures != null) {
        values['features'] = _sslFeatures;
        values['summary'] = _sslSummary;
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
        if (e.toString().contains('duplicate key')) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.info_outline, size: 32, color: C.primary),
              title: Text('This ${widget.def.singular} is already added'),
              content: Text('A ${widget.def.singular} with these details is already in Master Data, so it can\'t be added a second time.\n\nTo change it, close this window and use the Edit (pencil) button on the existing row instead.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
        } else {
          showError(context, e);
        }
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
                          final shown = !panel ? '.$tld' : def.table == 'vps_plan_prices' ? _text['plan_name']!.text : (def.table == 'hosting_plan_prices' || def.table == 'ssl_plan_prices') ? '${_text['plan_name']!.text}  ·  ${_text['months']!.text} mo' : def.table == 'vps_locations' ? '${_text['label']!.text}  (${_text['code']!.text})' : _text['label']!.text;
                          // An existing price keeps its extension; a new one is picked from 20i's list.
                          final locked = widget.row != null;
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            InkWell(
                              onTap: locked ? null : (panel ? _pickPanel : _pickTld),
                              child: InputDecorator(
                                decoration: fieldDecoration().copyWith(enabled: !locked, errorText: state.errorText, suffixIcon: locked ? const Icon(Icons.lock_outline, size: 18) : const Icon(Icons.arrow_drop_down)),
                                child: tld.isEmpty ? dropdownHint(f.hint) : Text(shown, style: T.bodyMd.copyWith(color: locked ? C.outline : null)),
                              ),
                            ),
                            if (_cost != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Market price: ${money(_cost!)} per ${def.table == 'vps_plan_prices' || def.table == 'vps_addon_prices' ? 'month' : panel ? 'period' : 'year'}', style: T.bodySm.copyWith(color: C.secondary))),
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
                            label: const Text('Pick from the list'),
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

/// What an SSL certificate type includes (warranty, validation level, ...), in its own window.
Future<void> _showSslDetails(BuildContext context, String title, String classCode, {List<String> features = const [], String summary = ''}) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(title, style: T.headlineSm),
              trailing: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: SslPackageDetails(classCode: classCode, features: features, summary: summary))),
          ]),
        ),
      ),
    );

/// One row in [_PickerDialog]: what is shown, and the value handed back when it is selected.
class _PickerItem<V> {
  const _PickerItem({required this.value, required this.title, required this.subtitle, required this.price, this.onInfo});
  final V value;
  final String title, subtitle, price;

  /// Opens a window with what is inside; when null there is no "View details" button.
  final void Function(BuildContext context)? onInfo;
}

/// The list shown when adding a hosting package, VPS, SSL certificate or add-on: one card per choice with its market price,
/// an optional "View details" button and a "Select" button.
class _PickerDialog<V> extends StatelessWidget {
  const _PickerDialog({required this.title, required this.items, required this.emptyText});
  final String title, emptyText;
  final List<_PickerItem<V>> items;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: T.headlineSm),
                  Text('Choose one to add.${items.any((i) => i.onInfo != null) ? ' Use "View details" to see what is inside first.' : ''}', style: T.bodySm.copyWith(color: C.secondary)),
                ]),
              ),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              children: [
                if (items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(emptyText)),
                for (final i in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(border: Border.all(color: C.outline.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.title, style: T.labelLg),
                          const SizedBox(height: 4),
                          Text(i.subtitle, style: T.bodySm.copyWith(color: C.secondary)),
                          const SizedBox(height: 4),
                          Text(i.price, style: T.labelLg.copyWith(color: C.primary)),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      if (i.onInfo != null) ...[
                        OutlinedButton.icon(icon: const Icon(Icons.info_outline, size: 16), label: const Text('View details'), onPressed: () => i.onInfo!(context)),
                        const SizedBox(width: 8),
                      ],
                      FilledButton(onPressed: () => Navigator.pop(context, i.value), child: const Text('Select')),
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// What a VPS plan comes with (memory, cores, disk), in its own window.
Future<void> _showVpsDetails(BuildContext context, String title, {int? cores, int? ramMb, int? diskGb}) {
  String gb(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  final rows = <(IconData, String, String)>[
    (Icons.memory, 'Memory', ramMb == null ? '—' : '${gb(ramMb / 1024)} GB'),
    (Icons.developer_board, 'CPU cores', cores == null ? '—' : '$cores'),
    (Icons.storage, 'SSD disk', diskGb == null ? '—' : '$diskGb GB'),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(title, style: T.headlineSm),
            trailing: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AppCard(
              child: Column(children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Icon(r.$1, size: 20, color: C.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(r.$2, style: T.bodyMd.copyWith(color: C.secondary))),
                      Text(r.$3, style: T.labelLg),
                    ]),
                  ),
                if (cores == null && ramMb == null && diskGb == null)
                  Text('The specs are not saved for this plan yet. Pick the plan again in Master Data > VPS.', style: T.bodySm.copyWith(color: C.secondary)),
              ]),
            ),
          ),
        ]),
      ),
    ),
  );
}
