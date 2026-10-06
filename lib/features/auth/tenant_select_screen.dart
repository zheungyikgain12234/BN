import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

class TenantSelectScreen extends StatefulWidget {
  const TenantSelectScreen({super.key});

  @override
  State<TenantSelectScreen> createState() => _TenantSelectScreenState();
}

class _TenantSelectScreenState extends State<TenantSelectScreen> with SingleTickerProviderStateMixin {
  static const _autoSeconds = 3;

  List<Tenant>? _tenants;
  Object? _error;
  Timer? _timer;
  int _left = _autoSeconds;
  bool _paused = false;
  bool _entering = false;
  Tenant? _selected;
  late final AnimationController _progress = AnimationController(vsync: this, duration: const Duration(seconds: _autoSeconds));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await tenantRepo.myTenants();
      if (!mounted) return;
      setState(() {
        _tenants = list;
        _selected = list.isEmpty ? null : list.first;
      });
      if (list.length == 1) _startAutoRedirect();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _startAutoRedirect() {
    _progress.forward(from: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _left -= 1);
      if (_left <= 0) {
        t.cancel();
        _enter();
      }
    });
  }

  void _pause() {
    _timer?.cancel();
    _progress.stop();
    setState(() => _paused = true);
  }

  void _enter([Tenant? tenant]) {
    final t = tenant ?? _selected;
    if (t == null || _entering) return;
    _timer?.cancel();
    setState(() => _entering = true);
    AppState.instance.selectTenant(t);
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: _error != null
          ? ErrorRetry(error: _error!, onRetry: _load)
          : _tenants == null
              ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
              : _content(_tenants!),
    );
  }

  Widget _content(List<Tenant> tenants) {
    final single = tenants.length == 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(Icons.domain_verification, size: 16, color: C.primary),
          const SizedBox(width: 4),
          Text('IDENTITY & ACCESS DIRECTORY', style: T.labelSm.copyWith(color: C.primary, letterSpacing: 0.9)),
        ]),
        const SizedBox(height: 8),
        Text('Select Company / Tenant Account', style: T.headlineLg),
        const SizedBox(height: 4),
        Text('Choose the organization environment you wish to manage in BizNest Hub.', style: T.bodyMd.copyWith(color: C.onSurfaceVariant)),
        const SizedBox(height: 24),
        if (single) ...[_banner(tenants.first), const SizedBox(height: 24)],
        if (tenants.isEmpty)
          _emptyState()
        else
          for (final t in tenants) ...[
            _TenantCard(tenant: t, selected: _selected?.id == t.id, onTap: () => single ? _enter(t) : setState(() => _selected = t)),
            const SizedBox(height: 16),
          ],
        _JoinTile(onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation flow is not available yet.')))),
        const SizedBox(height: 24),
        PrimaryButton(
          label: _entering ? 'Accessing Tenant Workspace...' : 'Enter Console Now',
          icon: _entering ? null : Icons.arrow_forward,
          loading: _entering,
          onPressed: _selected == null ? null : () => _enter(),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: authRepo.signOut,
          icon: const Icon(Icons.switch_account, size: 18, color: C.secondary),
          label: Text('Switch User Account', style: T.labelLg.copyWith(color: C.secondary)),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 15, color: C.outline),
          const SizedBox(width: 4),
          Flexible(child: Text('BizNest Cloud IAM • Session encrypted with TLS 1.3', style: T.labelSm.copyWith(color: C.outline))),
        ]),
      ],
    );
  }

  Widget _banner(Tenant t) {
    if (_paused) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.surfaceContainer, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.pause_circle_outline, size: 18, color: C.outline),
          const SizedBox(width: 8),
          Expanded(child: Text('Auto-redirect paused. Confirm entry below when ready.', style: T.bodySm.copyWith(color: C.onSurfaceVariant))),
          TextButton(onPressed: () => _enter(t), child: Text('Resume', style: T.labelSm.copyWith(color: C.primary))),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.primaryFixed.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 4, right: 8), child: Icon(Icons.circle, size: 12, color: C.primary)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Single Active Enterprise Detected', style: T.labelMd.copyWith(color: C.onPrimaryFixed)),
              const SizedBox(height: 2),
              Text.rich(TextSpan(style: T.bodySm.copyWith(color: C.onPrimaryFixedVariant, height: 1.4), children: [
                const TextSpan(text: 'Only 1 company associated with this account. Automatically redirecting to '),
                TextSpan(text: t.name, style: const TextStyle(fontWeight: FontWeight.w600, color: C.primary)),
                const TextSpan(text: ' in '),
                TextSpan(text: '${_left.clamp(0, _autoSeconds)}s', style: const TextStyle(fontWeight: FontWeight.w600, color: C.primary)),
                const TextSpan(text: '...'),
              ])),
            ]),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _pause,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Cancel Auto-Redirect', style: T.labelSm.copyWith(color: C.primary)),
          ),
        ]),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _progress,
          builder: (_, _) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: _progress.value, minHeight: 4, color: C.primary, backgroundColor: C.surfaceHighest.withValues(alpha: 0.6)),
          ),
        ),
      ]),
    );
  }

  Widget _emptyState() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          const Icon(Icons.business_outlined, size: 32, color: C.outline),
          const SizedBox(height: 8),
          Text('No organizations yet', style: T.headlineSm),
          const SizedBox(height: 4),
          Text('Your account is not linked to a company. Ask your reseller admin for an invitation.',
              style: T.bodySm.copyWith(color: C.onSurfaceVariant), textAlign: TextAlign.center),
        ]),
      );
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.selected, required this.onTap});
  final Tenant tenant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          color: C.surfaceLow,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: selected ? C.tertiary : C.outlineVariant, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(selected ? 'SELECTED ENVIRONMENT' : 'AVAILABLE ENVIRONMENT', style: T.labelSm.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5))),
            const Pill('Active / Verified', icon: Icons.verified, bg: C.tertiaryFixed, fg: C.onTertiaryFixedVariant),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [C.primary, C.primaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(tenant.initials, style: T.headlineMd.copyWith(color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(tenant.name, style: T.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.arrow_forward, size: 20, color: C.outline),
                ]),
                const SizedBox(height: 2),
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Icon(Icons.dns_outlined, size: 15, color: C.outline),
                  Text(tenant.code, style: T.bodySm.copyWith(color: C.outline, fontFamily: 'monospace')),
                  const Text('•', style: TextStyle(color: C.outlineVariant)),
                  Text(tenant.domain, style: T.bodySm.copyWith(color: C.onSurfaceVariant)),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(8)),
                  child: Wrap(spacing: 24, runSpacing: 8, children: [
                    _Stat('ASSIGNED ROLE', Icons.admin_panel_settings_outlined, C.primary, _roleLabel(tenant.role)),
                    _Stat('SUBSCRIBED POOL', Icons.verified_user_outlined, C.tertiary, '${tenant.seats} seats active'),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _roleLabel(String r) => switch (r) {
        'owner' || 'admin' => 'Primary Administrator',
        _ => r.isEmpty ? 'Member' : '${r[0].toUpperCase()}${r.substring(1)}',
      };
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.icon, this.color, this.value);
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: T.labelSm.copyWith(color: C.outline, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(value, style: T.labelMd),
        ]),
      ]);
}

class _JoinTile extends StatelessWidget {
  const _JoinTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: C.surfaceHighest, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.add_business_outlined, size: 22, color: C.outline),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Join or Register Another Organization', style: T.labelLg),
                  Text('Enter invitation code, or provision a secondary multi-cloud tenant', style: T.bodySm.copyWith(color: C.onSurfaceVariant)),
                ]),
              ),
              const Icon(Icons.chevron_right, size: 20, color: C.outline),
            ]),
          ),
        ),
      );
}
