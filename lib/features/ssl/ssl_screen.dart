import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import '../../data/stackcp_sso.dart';

/// SSL certificates with a native UI. Only certificates that have a price in Master Data > SSL prices are offered.
/// The reseller picks a certificate and period, names the site, chooses how to prove control of the domain, fills in the
/// certificate contact details and adds it to the basket; payment and assigning to a client work like domains.
class SslScreen extends StatefulWidget {
  const SslScreen({super.key});

  @override
  State<SslScreen> createState() => _SslScreenState();
}

class _SslScreenState extends State<SslScreen> {
  /// ISO 3166 alpha-2 codes (what 20i wants) for the countries offered, with the dialling prefix for the phone field.
  static const _countries = {
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
  static const _verification = {
    'email': 'Email',
    'dns': 'DNS record',
    'file': 'File upload',
  };
  static const _verificationHelp = {
    'email': 'An approval message is sent to admin@your-domain. That address must be able to receive email.',
    'dns': 'Add a DNS record to prove you control the domain. The record is shown in the SSL verification details after checkout.',
    'file': 'Upload a small file to your website to prove you control the domain. The file is shown in the SSL verification details after checkout.',
  };

  final _form = GlobalKey<FormState>();
  Map<String, List<SslPrice>>? _plans; // by 20i class code
  Object? _error;

  String? _selected; // class code
  final Map<String, SslPrice> _period = {};
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
  bool _added = false;

  List<TextEditingController> get _all => [_subdomain, _domain, _star, _org, _name, _phone, _address1, _address2, _address3, _city, _state, _zip];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = <String, List<SslPrice>>{};
      for (final p in await sslCartRepo.prices()) {
        plans.putIfAbsent(p.classCode, () => []).add(p);
      }
      if (mounted) setState(() { _plans = plans; _selected ??= plans.keys.firstOrNull; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// "https://www.Example.com/x" -> "example.com", or null when it isn't a plausible domain.
  String? _cleanDomain(String raw) {
    final d = raw.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').split('/').first;
    return RegExp(r'^[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)+$').hasMatch(d) ? d : null;
  }

  Future<void> _add() async {
    final plans = _plans;
    final type = _selected;
    if (plans == null || type == null) return;
    if (!_form.currentState!.validate()) return;
    final plan = _period[type] ?? plans[type]!.first;
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
      setState(() => _added = true);
      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to your basket, but not to the hosting panel basket: ${result.error}'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _certificate(String type, List<SslPrice> options) {
    final selected = _selected == type;
    final plan = _period[type] ?? options.first;
    return SizedBox(
      width: 300,
      child: AppCard(
        color: selected ? const Color(0xFFEAF6FD) : C.surfaceLowest,
        onTap: () => setState(() { _selected = type; _added = false; }),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? C.primary : C.outline, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(options.first.planName, style: T.headlineSm)),
          ]),
          const SizedBox(height: 4),
          Text(options.first.wildcard ? 'Covers every subdomain of your domain.' : 'Covers one site name.', style: T.bodySm.copyWith(color: C.secondary)),
          const SizedBox(height: 12),
          DropdownButtonFormField<SslPrice>(
            initialValue: plan,
            isExpanded: true,
            decoration: fieldDecoration(),
            items: [for (final p in options) DropdownMenuItem(value: p, child: Text(p.label, overflow: TextOverflow.ellipsis))],
            onChanged: (p) => setState(() { _period[type] = p!; _selected = type; _added = false; }),
          ),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {bool required = false, double width = 360, String? hint}) => SizedBox(
        width: width,
        child: LabeledField(
          label: label,
          required: required,
          child: TextFormField(controller: c, decoration: fieldDecoration(hint: hint), validator: required ? _required : null, onChanged: (_) => _added ? setState(() => _added = false) : null),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final plans = _plans;
    if (plans == null) return const Center(child: CircularProgressIndicator());
    final wildcard = _selected != null && plans[_selected]!.first.wildcard;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('SSL Certificates', style: T.headlineLg),
      const SizedBox(height: 4),
      Text('Secure a website with an SSL certificate. Buy it here, then assign it to a client from Purchased SSL.', style: T.bodyMd.copyWith(color: C.onSurfaceVariant)),
      const SizedBox(height: 16),
      if (plans.isEmpty)
        AppCard(child: Text('No SSL certificates set up yet. Add them in Master Data > SSL.', style: T.bodyMd))
      else
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [for (final e in plans.entries) _certificate(e.key, e.value)]),
            const SizedBox(height: 20),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Domain details', style: T.headlineSm),
                const SizedBox(height: 12),
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
                  _field('Domain', _domain, required: true, width: 300, hint: 'example.com'),
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
                      onChanged: (v) => setState(() { _verify = v!; _added = false; }),
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
                  onSelectionChanged: (s) => setState(() { _business = s.first; _added = false; }),
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
                        onChanged: (v) => setState(() { _country = v!; _added = false; }),
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
                        onChanged: (_) => _added ? setState(() => _added = false) : null,
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
              ]),
            ),
            const SizedBox(height: 16),
            _added
                ? Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => context.go(Routes.cart), icon: const Icon(Icons.check, size: 16), label: const Text('In basket')))
                : Align(alignment: Alignment.centerLeft, child: PrimaryButton(label: 'Add to Basket', icon: Icons.add_shopping_cart, expand: false, onPressed: _add)),
          ]),
        ),
    ]);
  }
}
