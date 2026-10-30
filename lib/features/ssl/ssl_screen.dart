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

/// SSL certificates, laid out like Hosting Packages and VPS: a tile per certificate, and "More info" opens what it includes
/// plus the order form (period, site name, how to verify the domain, contact details). Only certificates that have a price in
/// Master Data > SSL are offered. Payment and assigning to a client work like domains.
class SslScreen extends StatefulWidget {
  const SslScreen({super.key});

  @override
  State<SslScreen> createState() => _SslScreenState();
}

/// ISO 3166 alpha-2 codes (what 20i wants) for the countries offered, with the dialling prefix for the phone field.
const _countries = {
  'SG': ('Singapore', '+65'),
  'MY': ('Malaysia', '+60'),
  'HK': ('Hong Kong', '+852'),
  'US': ('United States of America', '+1'),
  'GB': ('United Kingdom', '+44'),
  'AU': ('Australia', '+61'),
  'CA': ('Canada', '+1'),
  'IN': ('India', '+91'),
  'ID': ('Indonesia', '+62'),
  'TH': ('Thailand', '+66'),
  'PH': ('Philippines', '+63'),
  'CN': ('China', '+86'),
  'JP': ('Japan', '+81'),
  'DE': ('Germany', '+49'),
  'FR': ('France', '+33'),
};
const _verification = {
  'email': 'Email',
  'dns': 'DNS record',
  'file': 'File upload',
};
const _verificationHelp = {
  'email': 'An approval message is sent to admin@your-domain. That address must be able to receive email.',
  'dns': 'Add a DNS record to prove you control the domain. The record is shown in the SSL verification details after checkout.',
  'file': 'Upload a small file to your website to prove you control the domain. The file is shown in the SSL verification details after checkout.',
};

/// What a certificate includes (warranty, validation level, ...). Also used by Master Data so a super admin can look inside one.
class SslPackageDetails extends StatelessWidget {
  const SslPackageDetails({super.key, required this.classCode, this.features = const [], this.summary = ''});
  final String classCode;

  /// What was saved from 20i when the certificate was picked in Master Data.
  final List<String> features;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final list = features;
    final blurb = summary;
    if (list.isEmpty) {
      return AppCard(child: Text('No details were saved for this certificate. Pick it again in Master Data > SSL.', style: T.bodyMd.copyWith(color: C.secondary)));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('What is included', style: T.headlineSm),
        const SizedBox(height: 4),
        if (blurb.isNotEmpty) ...[
          Text(blurb, style: T.bodySm.copyWith(color: C.secondary)),
          const SizedBox(height: 12),
        ] else
          const SizedBox(height: 8),
        for (final f in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: T.bodyMd)),
            ]),
          ),
      ]),
    );
  }
}

class _SslScreenState extends State<SslScreen> {
  Map<String, List<SslPrice>>? _plans; // by 20i class code
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = <String, List<SslPrice>>{};
      for (final p in await sslCartRepo.prices()) {
        plans.putIfAbsent(p.classCode, () => []).add(p);
      }
      for (final list in plans.values) {
        list.sort((a, b) => a.months.compareTo(b.months));
      }
      if (mounted) setState(() => _plans = plans);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(List<SslPrice> options) => showDialog<void>(context: context, builder: (_) => _SslDialog(options: options));

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final plans = _plans;
    if (plans == null) return const Center(child: CircularProgressIndicator());
    final list = plans.values.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SSL Certificates', style: T.headlineLg),
            const SizedBox(height: 4),
            Text('Secure a website with an SSL certificate. Buy it here, then assign it to a client from Purchased SSL.', style: T.bodyMd.copyWith(color: C.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('${list.length} certificate${list.length == 1 ? '' : 's'}', style: T.labelMd.copyWith(color: C.secondary)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Center(child: Text('No SSL certificates set up yet. Add them in Master Data > SSL.', style: T.bodyMd.copyWith(color: C.secondary))),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 340, mainAxisExtent: 290, crossAxisSpacing: 16, mainAxisSpacing: 16),
                itemBuilder: (_, i) => _SslTile(options: list[i], onOpen: () => _open(list[i])),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SslIcon extends StatelessWidget {
  const _SslIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.primary, C.primaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Icon(Icons.lock_outline, size: size * 0.5, color: Colors.white),
        ),
      );
}

const _maxYears = 10;

class _SslTile extends StatelessWidget {
  const _SslTile({required this.options, required this.onOpen});
  final List<SslPrice> options; // sorted by period, shortest first
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = options.first;
    final features = p.features;
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _SslIcon(size: 56),
          const SizedBox(width: 12),
          Expanded(child: Text(p.planName, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.headlineSm)),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in features.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.onSurfaceVariant))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(money(p.price / p.months * 12, p.currency), style: T.labelLg.copyWith(color: C.primary)),
              Text('per year', style: T.labelSm.copyWith(color: C.secondary)),
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

/// What one certificate includes, then the order form. [options] is the certificate at each period it is sold for.
class _SslDialog extends StatefulWidget {
  const _SslDialog({required this.options});
  final List<SslPrice> options;

  @override
  State<_SslDialog> createState() => _SslDialogState();
}

class _SslDialogState extends State<_SslDialog> {
  final _form = GlobalKey<FormState>();
  final _years = TextEditingController(text: '1');

  /// The certificate's rate for one year (its shortest billing period scaled to 12 months), for both our price and the market price.
  SslPrice get _base => widget.options.first;
  double get _yearly => _base.price / _base.months * 12;
  double get _yearlyCost => _base.cost / _base.months * 12;

  /// Whole years from 1 to 10, or null while the box is empty or out of range.
  int? get _termYears {
    final y = int.tryParse(_years.text.trim());
    return y != null && y >= 1 && y <= _maxYears ? y : null;
  }

  double _round(double v) => (v * 100).round() / 100;

  /// The certificate for the chosen term: what goes in the basket (selling price) and the panel basket (market price).
  SslPrice _forTerm(int years) => SslPrice(
        classCode: _base.classCode,
        planName: _base.planName,
        months: years * 12,
        price: _round(_yearly * years),
        currency: _base.currency,
        cost: _round(_yearlyCost * years),
        features: _base.features,
        summary: _base.summary,
      );
  final _subdomain = TextEditingController(text: 'www');
  final _domain = TextEditingController();
  final _star = TextEditingController(text: '*'); // shown (disabled) as the subdomain of a wildcard certificate
  String _verify = 'email';
  bool _business = false;
  final _org = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _address3 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();
  String _country = 'SG';
  bool _adding = false;

  List<TextEditingController> get _all => [_years, _subdomain, _domain, _star, _org, _name, _phone, _address1, _address2, _address3, _city, _state, _zip];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  /// "https://www.Example.com/x" -> "example.com", or null when it isn't a plausible domain.
  String? _cleanDomain(String raw) {
    final d = raw.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').split('/').first;
    return RegExp(r'^[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)+$').hasMatch(d) ? d : null;
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    final plan = _forTerm(_termYears!);
    final domain = _cleanDomain(_domain.text)!;
    final sub = plan.wildcard ? '*' : _subdomain.text.trim().toLowerCase();
    final hostname = sub.isEmpty ? domain : '$sub.$domain';
    String t(TextEditingController c) => c.text.trim();
    final contact = {
      'type': _business ? 'business' : 'individual',
      if (_business) 'organisation': t(_org),
      'name': t(_name),
      'country': _country,
      'telephone': '${_countries[_country]!.$2}.${t(_phone)}',
      'address': [t(_address1), t(_address2), t(_address3)].where((l) => l.isNotEmpty).join('\n'),
      'city': t(_city),
      'state': t(_state),
      'zip': t(_zip),
    };
    setState(() => _adding = true);
    try {
      final result = await withLoader(context, () async {
        // Adding the same certificate again replaces it, so drop the old copy from the 20i panel basket first (no duplicates there).
        final old = await sslCartRepo.idOf(hostname, plan.classCode);
        if (old != null) await sslCartRepo.remove(old);
        await sslCartRepo.add(hostname: hostname, plan: plan, verification: _verify, contact: contact);
        // Mirror into the hosting panel's basket (best effort; our own basket is the one that is paid).
        final res = await addSslToPanelBasket(
          hostname: hostname, domain: domain, planName: plan.planName, classCode: plan.classCode, months: plan.months,
          price: plan.cost, verification: _verify, contact: contact,
        );
        final panelId = res.ids['${plan.planName} ($hostname)'];
        if (panelId != null) await sslCartRepo.setPanelId(hostname, plan.classCode, panelId);
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

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _field(String label, TextEditingController c, {bool required = false, double width = 360, String? hint}) => SizedBox(
        width: width,
        child: LabeledField(
          label: label,
          required: required,
          child: TextFormField(controller: c, decoration: fieldDecoration(hint: hint), validator: required ? _required : null),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _base;
    final term = _termYears;
    final wildcard = p.wildcard;
    final canBuy = AppState.instance.canBuy;
    return Dialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
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
                      const _SslIcon(size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.planName, style: T.headlineMd),
                          const SizedBox(height: 6),
                          Text('${money(_yearly, p.currency)} per year', style: T.labelLg.copyWith(color: C.primary)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  SslPackageDetails(classCode: p.classCode, features: p.features, summary: p.summary),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Order', style: T.headlineSm),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 240,
                        child: LabeledField(
                          label: 'How many years',
                          required: true,
                          helper: 'Up to $_maxYears years',
                          child: TextFormField(
                            controller: _years,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                            decoration: fieldDecoration(hint: '1 to $_maxYears'),
                            onChanged: (_) => setState(() {}),
                            validator: (_) => term == null ? 'Enter 1 to $_maxYears years' : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [
                        SizedBox(
                          width: 140,
                          child: LabeledField(
                            label: 'Subdomain',
                            child: TextFormField(
                              controller: wildcard ? _star : _subdomain,
                              enabled: !wildcard,
                              decoration: fieldDecoration(hint: 'www'),
                              validator: (v) => wildcard || RegExp(r'^[a-z0-9-]*$', caseSensitive: false).hasMatch((v ?? '').trim()) ? null : 'Letters, numbers, dashes',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 300,
                          child: LabeledField(
                            label: 'Domain',
                            required: true,
                            child: TextFormField(
                              controller: _domain,
                              decoration: fieldDecoration(hint: 'example.com'),
                              validator: (v) => _cleanDomain(v ?? '') == null ? 'Enter a domain, e.g. example.com' : null,
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 300,
                        child: LabeledField(
                          label: 'Verification method',
                          helper: _verificationHelp[_verify],
                          child: DropdownButtonFormField<String>(
                            initialValue: _verify,
                            isExpanded: true,
                            decoration: fieldDecoration(),
                            items: [for (final e in _verification.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                            onChanged: (v) => setState(() => _verify = v!),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Certificate contact details', style: T.headlineSm),
                      const SizedBox(height: 4),
                      Text('The certificate authority needs a county/state/province, even where it is not normally part of the address.', style: T.bodySm.copyWith(color: C.secondary)),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [ButtonSegment(value: false, label: Text('Individual')), ButtonSegment(value: true, label: Text('Business'))],
                        selected: {_business},
                        onSelectionChanged: (s) => setState(() => _business = s.first),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [
                        if (_business) _field('Organisation', _org, required: true),
                        _field('Full name', _name, required: true),
                        SizedBox(
                          width: 360,
                          child: LabeledField(
                            label: 'Country',
                            required: true,
                            child: DropdownButtonFormField<String>(
                              initialValue: _country,
                              isExpanded: true,
                              decoration: fieldDecoration(),
                              items: [for (final e in _countries.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
                              onChanged: (v) => setState(() => _country = v!),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: LabeledField(
                            label: 'Telephone',
                            required: true,
                            child: TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              decoration: fieldDecoration(hint: 'Number without the country code').copyWith(prefixText: '${_countries[_country]!.$2}  '),
                              validator: (v) => RegExp(r'^[0-9 ]{5,}$').hasMatch((v ?? '').trim()) ? null : 'Digits only, e.g. 60000000',
                            ),
                          ),
                        ),
                        _field('Address line 1', _address1, required: true),
                        _field('Address line 2', _address2),
                        _field('Address line 3', _address3),
                        _field('City', _city, required: true),
                        _field('County / State / Province', _state, required: true),
                        _field('Zip code', _zip, width: 200),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: Text('Total', style: T.labelLg)),
                        Text(term == null ? '—' : money(_round(_yearly * term), p.currency), style: T.labelLg.copyWith(color: C.primary)),
                      ]),
                      const SizedBox(height: 14),
                      if (canBuy)
                        PrimaryButton(label: 'Add to basket', icon: Icons.add_shopping_cart, loading: _adding, onPressed: _add)
                      else
                        Text('Only a reseller admin can buy.', style: T.bodySm.copyWith(color: C.secondary), textAlign: TextAlign.center),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
