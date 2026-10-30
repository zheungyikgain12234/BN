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

/// Hosting Packages, laid out like the software store and the VPS page: a tile per plan, and "More info" opens the full
/// package contents plus the order form (billing period and the domain the package is for). Only plans that have a price in
/// Master Data > Hosting Packages are offered; their contents were copied from 20i when the plan was picked there.
class HostingScreen extends StatefulWidget {
  const HostingScreen({super.key});

  @override
  State<HostingScreen> createState() => _HostingScreenState();
}

class _HostingScreenState extends State<HostingScreen> {
  Map<String, List<HostingPrice>>? _plans; // by 20i package type id
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plans = <String, List<HostingPrice>>{};
      for (final p in await hostingCartRepo.prices()) {
        plans.putIfAbsent(p.packageTypeId, () => []).add(p);
      }
      for (final list in plans.values) {
        list.sort((a, b) => a.months.compareTo(b.months));
      }
      if (mounted) setState(() => _plans = plans);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(List<HostingPrice> options) => showDialog<void>(context: context, builder: (_) => _HostingDialog(options: options));

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
            Text('Hosting Packages', style: T.headlineLg),
            const SizedBox(height: 16),
            Text('${list.length} plan${list.length == 1 ? '' : 's'}', style: T.labelMd.copyWith(color: C.secondary)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Center(child: Text('No hosting plans set up yet. Add them in Master Data > Hosting Packages.', style: T.bodyMd.copyWith(color: C.secondary))),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 340, mainAxisExtent: 270, crossAxisSpacing: 16, mainAxisSpacing: 16),
                itemBuilder: (_, i) => _PlanCard(options: list[i], onOpen: () => _open(list[i])),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Longest term that can be ordered (10 years, like VPS).
const _maxMonths = 120;

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
          child: Icon(Icons.cloud_outlined, size: size * 0.5, color: Colors.white),
        ),
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.options, required this.onOpen});
  final List<HostingPrice> options; // sorted by billing period, shortest first
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = options.first;
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _PlanIcon(size: 56),
          const SizedBox(width: 12),
          Expanded(child: Text(p.planName, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.headlineSm)),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in p.features.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.check, size: 14, color: C.primary),
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
              Text(money(p.price / p.months, p.currency), style: T.labelLg.copyWith(color: C.primary)),
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

/// A limit shown as in 20i's package editor: INF means unlimited; webspace and bandwidth are in MB.
String _limit(Object? v, {bool mb = false}) {
  if (v == null) return '—';
  if (v == 'INF') return 'Unlimited';
  return mb ? '$v MB' : '$v';
}

/// 20i's package limits, in the order its package editor shows them.
const _limitRows = <(String, String, bool)>[
  ('Webspace', 'webspace', true),
  ('Bandwidth', 'bandwidth', true),
  ('MySQL Databases', 'mysqlDatabases', false),
  ('Additional FTP', 'additionalFtpUsers', false),
  ('Subdomains', 'subdomains', false),
  ('Additional Domains', 'domains', false),
];

/// 20i's package features, grouped and labelled like its package editor. The second value is the flag in the plan's limits.
const _featureGroups = <(String, List<(String, String)>)>[
  ('CDN', [('Edge Caching', 'cdnCaching'), ('Website Optimisation Suite', 'cdnOptimisation'), ('Block Visitors', 'blockVisitors'), ('CDN Statistics', 'cdnStatistics'), ('Security Headers', 'cdnSecurityHeaders')]),
  ('Web Files', [('File Manager', 'fileManager'), ('FTP Accounts', 'ftp'), ('Backup/Restore', 'backups'), ('Website Builder', 'webBuilder'), ('File Permission', 'filePermissions'), ('Git Version Control', 'gitVersionControl')]),
  ('Email', [('Set Notification Threshold', 'canSetQuotaNotification'), ('Catch-All Forwarders', 'mailCatchAllForwarders'), ('Junk Mail Filters', 'mailJunkFilters'), ('Webmail', 'webmail'), ('Email Summary', 'emailSummary'), ('Email Migration', 'imapSync'), ('Domainkeys (DKIM)', 'dkimSignatures'), ('DMARC Wizard', 'dmarcWizard')]),
  ('Web Tools', [('PHPMyAdmin', 'phpMyAdmin'), ('Remote MySQL Access', 'remoteMysql'), ('Change PHP Version', 'switchPhpVersion'), ('PHP Configuration', 'phpConfig'), ('Scheduled Tasks', 'scheduledTasks'), ('Web Redirects', 'webRedirect'), ('Sitemap Generator', 'sitemapGenerator'), ('Custom Errors', 'htaccessErrors'), ('Auto Diagnostics', 'autoDiagnostics'), ('Maintenance Mode', 'maintenanceMode')]),
  ('Domain Names', [('Change Nameservers', 'nameservers'), ('Domain Privacy', 'domainPrivacy'), ('Manage Contacts', 'domainContacts'), ('Manage DNS', 'dns'), ('DNSSEC', 'dnsSec'), ('Transfer Away', 'pushTransfer'), ('WHOIS', 'whois'), ('Custom Doc Root (All Domains)', 'customDocRoot'), ('Custom Doc Root (Primary Domain)', 'customPrimaryDocRoot'), ('Make Primary Domain', 'makePrimaryDomain')]),
  ('Security', [('SSH Access', 'ssh'), ('Hotlink Protection', 'hotlinkProtection'), ('Free SSL', 'freeSsl'), ('Allow External SSL', 'allowExternalSsl'), ('Password Protection', 'passwordProtectedDirectories'), ('Directory Indexing', 'directoryIndexing'), ('Malware Scan', 'malwareScan'), ('Malware Report', 'malwareReport'), ('Auto activate free SSL', 'autoFreeSsl'), ('Allow Force SSL Redirect', 'allowForceSsl')]),
  ('Logs and Statistics', [('AWStats', 'awstats'), ('Webalizer', 'webalizer'), ('Access/Error Logs', 'accessErrorLogs'), ('Mail Logs', 'mailLogs')]),
  ('Side bar', [('Account Information', 'accountSummary'), ('Temporary URL', 'temporaryURL'), ('Primary FTP Lock', 'primaryFtpUnlock'), ('Usage Information', 'usageInformation'), ('Nameservers Setup', 'nameserverCheck'), ('View Bandwidth Stats', 'statsBandwidth'), ('View Disk Usage Stats', 'statsDisk')]),
  ('General Information', [('Google Translate', 'googleTranslate')]),
];

/// A plan's limits and feature list from 20i. Included features get a green tick, the rest a grey cross (not clickable).
/// Also used by Master Data so a super admin can look inside a plan before adding it.
class HostingPackageDetails extends StatelessWidget {
  const HostingPackageDetails({super.key, required this.limits});
  final Map<String, dynamic> limits;

  Widget _feature(String label, bool on) => Row(children: [
        Icon(on ? Icons.check_circle : Icons.cancel, size: 16, color: on ? Colors.green.shade600 : Colors.red.shade300),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: T.bodySm.copyWith(color: on ? C.onSurface : C.outline), overflow: TextOverflow.ellipsis)),
      ]);

  @override
  Widget build(BuildContext context) {
    if (limits.isEmpty) {
      return AppCard(child: Text('The full package details are not saved for this plan yet. Pick the plan again in Master Data > Hosting Packages.', style: T.bodyMd.copyWith(color: C.secondary)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Package Limits', style: T.headlineSm),
          const SizedBox(height: 12),
          Wrap(spacing: 24, runSpacing: 12, children: [
            for (final r in _limitRows)
              SizedBox(
                width: 160,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.$1, style: T.labelSm.copyWith(color: C.secondary)),
                  const SizedBox(height: 2),
                  Text(_limit(limits[r.$2], mb: r.$3), style: T.labelLg),
                ]),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Package Features', style: T.headlineSm),
          for (final g in _featureGroups) ...[
            const SizedBox(height: 16),
            Text(g.$1, style: T.labelLg),
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 6, children: [
              for (final f in g.$2) SizedBox(width: 220, child: _feature(f.$1, limits[f.$2] == true)),
            ]),
          ],
        ]),
      ),
    ]);
  }
}

/// Everything in one plan, then the order form. [options] is the plan at each billing period it is sold for.
class _HostingDialog extends StatefulWidget {
  const _HostingDialog({required this.options});
  final List<HostingPrice> options;

  @override
  State<_HostingDialog> createState() => _HostingDialogState();
}

class _HostingDialogState extends State<_HostingDialog> {
  final _form = GlobalKey<FormState>();
  final _domain = TextEditingController();
  final _years = TextEditingController(text: '1');
  final _extraMonths = TextEditingController(text: '0');
  bool _adding = false;

  /// The package's rate for one month (its shortest billing period divided out), for both our price and the market price.
  HostingPrice get _base => widget.options.first;
  double get _monthly => _base.price / _base.months;
  double get _monthlyCost => _base.cost / _base.months;

  @override
  void dispose() {
    _domain.dispose();
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
    return total >= 1 && total <= _maxMonths ? total : null;
  }

  double _round(double v) => (v * 100).round() / 100;

  /// The package for the chosen term: what goes in the basket (selling price) and the panel basket (market price).
  HostingPrice _forTerm(int months) => HostingPrice(
        packageTypeId: _base.packageTypeId,
        planName: _base.planName,
        months: months,
        price: _round(_monthly * months),
        currency: _base.currency,
        cost: _round(_monthlyCost * months),
        features: _base.features,
        limits: _base.limits,
      );

  /// "https://www.Example.com/x" -> "example.com", or null when it isn't a plausible domain.
  String? _clean(String raw) {
    final d = raw.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^www\.'), '').split('/').first;
    return RegExp(r'^[a-z0-9][a-z0-9-]*(\.[a-z0-9-]+)+$').hasMatch(d) ? d : null;
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    final domain = _clean(_domain.text)!;
    final p = _forTerm(_termMonths!);
    setState(() => _adding = true);
    try {
      final result = await withLoader(context, () async {
        // Adding the same domain again replaces it, so drop the old copy from the 20i panel basket first (no duplicates there).
        final old = await hostingCartRepo.idOf(domain);
        if (old != null) await hostingCartRepo.remove(old);
        await hostingCartRepo.add(domain, p);
        // Mirror into the hosting panel's basket (best effort; our own basket is the one that is paid).
        final res = await addHostingToPanelBasket(domain: domain, typeId: p.packageTypeId, months: p.months, price: p.cost);
        final panelId = res.ids[domain];
        if (panelId != null) await hostingCartRepo.setPanelId(domain, panelId);
        return res;
      }, message: 'Adding to your basket...');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(result.error == null ? '${p.planName} added to your basket' : 'Added to your basket, but not to the hosting panel basket: ${result.error}'),
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

  @override
  Widget build(BuildContext context) {
    final p = _base;
    final term = _termMonths;
    final limits = p.limits;
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppCard(
                  child: Row(children: [
                    const _PlanIcon(size: 64),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.planName, style: T.headlineMd),
                        const SizedBox(height: 4),
                        for (final f in p.features) Text(f, style: T.bodySm.copyWith(color: C.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Text('${money(_monthly, p.currency)} per month', style: T.labelLg.copyWith(color: C.primary)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Form(
                    key: _form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Order', style: T.headlineSm),
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
                              decoration: fieldDecoration(hint: '0 to ${_maxMonths ~/ 12}'),
                              onChanged: (_) => setState(() {}),
                              validator: (_) => term == null ? 'Term: 1 month to ${_maxMonths ~/ 12} years' : null,
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
                        child: Text(term == null ? 'Enter 1 month up to ${_maxMonths ~/ 12} years ($_maxMonths months).' : '$term months in total', style: T.bodySm.copyWith(color: C.secondary)),
                      ),
                      const SizedBox(height: 14),
                      LabeledField(
                        label: 'Domain name',
                        required: true,
                        helper: 'The domain this hosting package is for',
                        child: TextFormField(
                          controller: _domain,
                          decoration: fieldDecoration(hint: 'e.g. mybusiness.com'),
                          validator: (v) => _clean(v ?? '') == null ? 'Enter a domain, e.g. mybusiness.com' : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: Text('Total', style: T.labelLg)),
                        Text(term == null ? '—' : money(_round(_monthly * term), p.currency), style: T.labelLg.copyWith(color: C.primary)),
                      ]),
                      const SizedBox(height: 14),
                      if (canBuy)
                        PrimaryButton(label: 'Add to basket', icon: Icons.add_shopping_cart, loading: _adding, onPressed: _add)
                      else
                        Text('Only a reseller admin can buy.', style: T.bodySm.copyWith(color: C.secondary), textAlign: TextAlign.center),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                HostingPackageDetails(limits: limits),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
