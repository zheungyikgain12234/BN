import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/stackcp_sso.dart';

/// VPS catalogue, laid out like the software store: a tile per plan with its specs and price per month. "More info" opens the
/// order form (term in years, operating system, location, optional add-ons). Only plans that have a price in
/// Master Data > VPS prices are offered. Add-ons (cPanel licence, snapshot backup, extra disk) come from Master Data > VPS
/// add-on prices and are ordered from 20i right after the server is created. Left out for now: extra IP addresses and one-click apps.
class VpsScreen extends StatefulWidget {
  const VpsScreen({super.key});

  @override
  State<VpsScreen> createState() => _VpsScreenState();
}

class _VpsScreenState extends State<VpsScreen> {
  List<VpsPrice>? _plans;
  List<VpsOs> _os = const [];
  List<VpsAddonPrice> _addons = const [];
  Map<String, String> _locations = const {}; // code -> name shown to customers
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = await vpsCartRepo.prices();
      final os = await vpsCartRepo.osOptions();
      // Add-ons are optional: if their table isn't created yet the plans must still work.
      final addons = await vpsCartRepo.addonPrices().catchError((_) => <VpsAddonPrice>[]);
      final locations = await vpsCartRepo.locations().catchError((_) => <({String code, String label})>[]);
      if (mounted) setState(() { _plans = plans; _os = os; _addons = addons; _locations = {for (final l in locations) l.code: l.label}; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(VpsPrice plan) => showDialog<void>(
        context: context,
        builder: (_) => _VpsOrderDialog(plan: plan, os: _os, addons: _addons, locations: _locations),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final plans = _plans;
    if (plans == null) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('VPS', style: T.headlineLg),
            const SizedBox(height: 16),
            Text('${plans.length} plan${plans.length == 1 ? '' : 's'}', style: T.labelMd.copyWith(color: C.secondary)),
            const SizedBox(height: 8),
            if (plans.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Center(child: Text('No VPS plans set up yet. Add them in Master Data > VPS prices.', style: T.bodyMd.copyWith(color: C.secondary))),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: plans.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 340, mainAxisExtent: 236, crossAxisSpacing: 16, mainAxisSpacing: 16),
                itemBuilder: (_, i) => _PlanCard(plan: plans[i], onOpen: () => _open(plans[i])),
              ),
          ]),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onOpen});
  final VpsPrice plan;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _PlanIcon(size: 56),
          const SizedBox(width: 12),
          Expanded(child: Text(plan.planName, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.headlineSm)),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: plan.specLines.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final s in plan.specLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.check, size: 14, color: C.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.onSurfaceVariant))),
                      ]),
                    ),
                ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(money(plan.pricePerMonth, plan.currency), style: T.labelLg.copyWith(color: C.primary)),
              Text('per month', style: T.labelSm.copyWith(color: C.secondary)),
            ]),
          ),
          FilledButton(
            onPressed: onOpen,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('More info'),
          ),
        ]),
      ]),
    );
  }
}

/// Server icon on the same green tile the software store uses when an app has no image.
class _PlanIcon extends StatelessWidget {
  const _PlanIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.primary, C.primaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Icon(Icons.dns_outlined, size: size * 0.5, color: Colors.white),
        ),
      );
}

/// The order form for one plan. Every field has its label above it. Adding puts the server in the basket (ours, and
/// mirrored into the hosting panel's basket) and closes the form.
class _VpsOrderDialog extends StatefulWidget {
  const _VpsOrderDialog({required this.plan, required this.os, required this.addons, required this.locations});
  final VpsPrice plan;
  final List<VpsOs> os;
  final List<VpsAddonPrice> addons;
  final Map<String, String> locations;

  @override
  State<_VpsOrderDialog> createState() => _VpsOrderDialogState();
}

class _VpsOrderDialogState extends State<_VpsOrderDialog> {
  final _form = GlobalKey<FormState>();
  final _years = TextEditingController(text: '1');
  final _extraMonths = TextEditingController(text: '0');
  VpsOs? _os;
  String? _location;
  VpsAddonPrice? _cpanel, _backup, _disk;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _os = widget.os.firstOrNull;
    _location = widget.locations.keys.firstOrNull;
  }

  @override
  void dispose() {
    _years.dispose();
    _extraMonths.dispose();
    super.dispose();
  }

  /// The whole term in months (years x 12 + months), or null while it is empty or outside 1 month to 10 years.
  int? get _termMonths {
    final y = int.tryParse(_years.text.trim()) ?? (_years.text.trim().isEmpty ? 0 : null);
    final m = int.tryParse(_extraMonths.text.trim()) ?? (_extraMonths.text.trim().isEmpty ? 0 : null);
    if (y == null || m == null || m > 11) return null;
    final total = y * 12 + m;
    return total >= 1 && total <= maxVpsMonths ? total : null;
  }

  List<VpsAddonPrice> get _picked => [_cpanel, _backup, _disk].whereType<VpsAddonPrice>().toList();

  /// Add-ons run for the server's whole term, so they cost their monthly price x the same number of months.
  double? get _total {
    final t = _termMonths;
    return t == null ? null : widget.plan.totalForMonths(t) + _picked.fold<double>(0, (s, a) => s + a.totalForMonths(t));
  }

  /// 20i needs a name for each server. Resellers don't choose one: it is generated, e.g. vps-483920.
  String _newServerName() => 'vps-${Random().nextInt(900000) + 100000}';

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    final months = _termMonths!;
    final os = _os;
    final location = _location;
    if (os == null) {
      showError(context, 'No operating systems are set up yet. Add them in Master Data > VPS operating systems.');
      return;
    }
    if (location == null) {
      showError(context, 'No locations are set up yet. Add them in Master Data > VPS locations.');
      return;
    }
    final plan = widget.plan;
    final addons = _picked;
    final name = _newServerName();
    setState(() => _adding = true);
    try {
      final result = await withLoader(context, () async {
        await vpsCartRepo.add(serverName: name, plan: plan, months: months, os: os, location: location, addons: addons);
        // Mirror into the hosting panel's basket (best effort; our own basket is the one that is paid).
        final res = await addVpsToPanelBasket(
          serverName: name, vpsType: plan.vpsType, months: months, price: plan.costForMonths(months), osCode: os.code, location: location, // the panel basket holds 20i's own prices
          addons: [for (final a in addons) (spec: a.spec, months: months, price: a.costForMonths(months))],
        );
        final panelId = res.ids[name];
        if (panelId != null) await vpsCartRepo.setPanelId(name, panelId);
        return res;
      }, message: 'Adding to your basket...');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(result.error == null ? '${plan.planName} added to your basket' : 'Added to your basket, but not to the hosting panel basket: ${result.error}'),
          persist: false,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'View basket', onPressed: () => router.go(Routes.cart)),
        ));
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        showError(context, e);
      }
    }
  }

  /// A labelled "None" + one entry per priced add-on of a kind.
  Widget _addonField(String label, List<VpsAddonPrice> options, VpsAddonPrice? value, ValueChanged<VpsAddonPrice?> onChanged) {
    final list = options.where((a) => a.currency == widget.plan.currency).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LabeledField(
        label: label,
        child: DropdownButtonFormField<VpsAddonPrice?>(
          initialValue: value,
          isExpanded: true,
          decoration: fieldDecoration(),
          items: [
            const DropdownMenuItem<VpsAddonPrice?>(value: null, child: Text('None')),
            for (final a in list) DropdownMenuItem<VpsAddonPrice?>(value: a, child: Text('${a.label} · ${money(a.pricePerMonth, a.currency)} per month', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (a) => setState(() => onChanged(a)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final w = widget;
    final canBuy = AppState.instance.canBuy;
    final cpanel = [for (final a in w.addons) if (a.isCpanel) a];
    final backup = [for (final a in w.addons) if (a.isBackup) a];
    final disk = [for (final a in w.addons) if (a.isDisk) a]..sort((a, b) => a.diskGb.compareTo(b.diskGb));
    final hasAddons = [cpanel, backup, disk].any((l) => l.isNotEmpty);
    final term = _termMonths;
    return Dialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AppCard(
                    child: Row(children: [
                      const _PlanIcon(size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.planName, style: T.headlineMd),
                          const SizedBox(height: 4),
                          for (final s in p.specLines) Text(s, style: T.bodySm.copyWith(color: C.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Text('${money(p.pricePerMonth, p.currency)} per month', style: T.labelLg.copyWith(color: C.primary)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Server', style: T.headlineSm),
                      const SizedBox(height: 12),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: LabeledField(
                            label: 'How many years',
                            required: true,
                            child: TextFormField(
                              controller: _years,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                              decoration: fieldDecoration(hint: '0 to $maxVpsYears'),
                              onChanged: (_) => setState(() {}),
                              validator: (_) => term == null ? 'Term: 1 month to $maxVpsYears years' : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            label: 'How many months',
                            required: true,
                            child: TextFormField(
                              controller: _extraMonths,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                              decoration: fieldDecoration(hint: '0 to 11'),
                              onChanged: (_) => setState(() {}),
                              validator: (_) => term == null ? ' ' : null,
                            ),
                          ),
                        ),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(term == null ? 'Enter 1 month up to $maxVpsYears years ($maxVpsMonths months).' : '$term months in total', style: T.bodySm.copyWith(color: C.secondary)),
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        label: 'Operating system',
                        required: true,
                        child: DropdownButtonFormField<VpsOs>(
                          initialValue: _os,
                          isExpanded: true,
                          hint: dropdownHint('Select an operating system'),
                          decoration: fieldDecoration(),
                          items: [for (final o in w.os) DropdownMenuItem(value: o, child: Text(o.label, overflow: TextOverflow.ellipsis))],
                          onChanged: (o) => setState(() => _os = o),
                          validator: (o) => o == null ? 'No operating systems are set up yet' : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        label: 'Location',
                        required: true,
                        child: DropdownButtonFormField<String>(
                          initialValue: _location,
                          isExpanded: true,
                          hint: dropdownHint('Select a location'),
                          decoration: fieldDecoration(),
                          items: [for (final e in w.locations.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                          onChanged: (l) => setState(() => _location = l),
                          validator: (l) => l == null ? 'No locations are set up yet' : null,
                        ),
                      ),
                    ]),
                  ),
                  if (hasAddons) ...[
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Add-ons (optional)', style: T.headlineSm),
                        const SizedBox(height: 12),
                        _addonField('cPanel licence', cpanel, _cpanel, (a) => _cpanel = a),
                        _addonField('Snapshot backup', backup, _backup, (a) => _backup = a),
                        _addonField('Extra disk', disk, _disk, (a) => _disk = a),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Summary', style: T.headlineSm),
                      const SizedBox(height: 8),
                      _line('${p.planName}${term == null ? '' : ' · ${termLabel(term)}'}', term == null ? null : p.totalForMonths(term), p.currency),
                      for (final a in _picked) _line('${a.label}${term == null ? '' : ' · ${termLabel(term)}'}', term == null ? null : a.totalForMonths(term), a.currency),
                      const Divider(height: 20),
                      _line('Total', _total, p.currency, bold: true),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (canBuy)
                    PrimaryButton(label: 'Add to basket', icon: Icons.add_shopping_cart, loading: _adding, onPressed: _add)
                  else
                    Text('Only a reseller admin can buy.', style: T.bodySm.copyWith(color: C.secondary), textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _line(String label, double? amount, String currency, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: bold ? T.labelLg : T.bodyMd, overflow: TextOverflow.ellipsis)),
          Text(amount == null ? '—' : money(amount, currency), style: bold ? T.labelLg.copyWith(color: C.primary) : T.bodyMd),
        ]),
      );
}
