import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

class _NavGroup {
  const _NavGroup(this.title, this.items);
  final String? title;
  final List<_NavItem> items;
}

final _nav = <_NavGroup>[
  const _NavGroup(null, [_NavItem('Home', Icons.dashboard_outlined, Routes.home)]),
  _NavGroup('Catalog & Services', [
    _NavItem('Microsoft CSP', Icons.grid_view, Routes.section('microsoft-csp')),
    _NavItem('License-based services', Icons.vpn_key_outlined, Routes.section('license-services')),
    _NavItem('Trial Services', Icons.hourglass_top, Routes.section('trial-services')),
    _NavItem('Azure Reservations', Icons.cloud_queue, Routes.section('azure-reservations')),
    const _NavItem('Software', Icons.apps, Routes.software),
    _NavItem('Multi-publisher', Icons.hub_outlined, Routes.section('multi-publisher')),
    _NavItem('Web Hosting', Icons.dns_outlined, Routes.section('web-hosting')),
    const _NavItem('Domain Search', Icons.language, Routes.domainSearch),
  ]),
  _NavGroup('Operations', [
    _NavItem('Manage', Icons.inventory_2_outlined, Routes.section('manage')),
    _NavItem('Transactions', Icons.receipt_long_outlined, Routes.section('transactions')),
    _NavItem('Insights', Icons.insights, Routes.section('insights')),
    _NavItem('Reseller Administration', Icons.corporate_fare, Routes.section('reseller-administration')),
    _NavItem('Support', Icons.contact_support_outlined, Routes.section('support')),
    _NavItem('API Integrations', Icons.api, Routes.section('api-integrations')),
    _NavItem('Settings', Icons.settings_outlined, Routes.section('settings')),
  ]),
];

/// Top bar + left sidebar used by every post-login screen. Sidebar collapses to a drawer on narrow widths.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  bool _isActive(_NavItem i) {
    if (i.path == Routes.software) return location == Routes.software || location.startsWith('/products/');
    return location == i.path;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final sidebar = _Sidebar(isActive: _isActive, onSelect: (p) {
        if (!wide) Navigator.of(context).maybePop();
        context.go(p);
      });
      return Scaffold(
        backgroundColor: C.surface,
        appBar: PreferredSize(preferredSize: const Size.fromHeight(56), child: _TopBar(width: c.maxWidth, showMenu: !wide)),
        drawer: wide ? null : Drawer(width: 280, backgroundColor: C.surfaceLow, child: SafeArea(child: sidebar)),
        body: Row(children: [
          if (wide) SizedBox(width: 256, child: ColoredBox(color: C.surfaceLow, child: sidebar)),
          Expanded(child: child),
        ]),
      );
    });
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.isActive, required this.onSelect});
  final bool Function(_NavItem) isActive;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final g in _nav) ...[
          if (g.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(g.title!.toUpperCase(), style: T.labelSm.copyWith(color: C.secondary, fontWeight: FontWeight.w600, letterSpacing: 0.9)),
            ),
          for (final i in g.items) _NavTile(item: i, active: isActive(i), onTap: () => onSelect(i.path)),
        ],
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : C.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active ? C.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: C.surfaceHigh,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(item.icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(child: Text(item.label, overflow: TextOverflow.ellipsis, style: T.labelMd.copyWith(color: fg, fontWeight: active ? FontWeight.w700 : FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.width, required this.showMenu});
  final double width;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return Material(
      color: C.surfaceLowest,
      elevation: 0,
      shadowColor: const Color(0x0A000000),
      child: Container(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1))]),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          if (showMenu)
            Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer())),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.hub, size: 20, color: Colors.white),
          ),
          if (width >= 480) ...[
            const SizedBox(width: 12),
            Text('BizNest Hub', style: T.headlineSm.copyWith(fontWeight: FontWeight.w700)),
          ],
          const SizedBox(width: 16),
          if (width >= 768)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 576),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      style: T.bodySm,
                      decoration: fieldDecoration(hint: 'Search software, domains, licenses...', prefix: Icons.search).copyWith(
                        contentPadding: EdgeInsets.zero,
                        hintStyle: T.bodySm.copyWith(color: C.secondary),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          if (width >= 560)
            TextButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('BizBot is not available yet.'))),
              style: TextButton.styleFrom(
                backgroundColor: C.secondaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.auto_awesome, size: 16, color: C.primary),
              label: Text('Ask BizBot', style: T.labelSm.copyWith(fontWeight: FontWeight.w600)),
            ),
          Stack(children: [
            IconButton(icon: const Icon(Icons.notifications_none, size: 22, color: C.onSurfaceVariant), onPressed: () {}),
            const Positioned(top: 10, right: 10, child: CircleAvatar(radius: 4, backgroundColor: C.error)),
          ]),
          if (width >= 640) IconButton(icon: const Icon(Icons.download_outlined, size: 22, color: C.onSurfaceVariant), onPressed: () {}),
          if (width >= 1100)
            ListenableBuilder(
              listenable: state,
              builder: (_, _) => Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.business, size: 16, color: C.secondary),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(state.tenant?.name ?? '', overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 6),
                  Pill((state.tenant?.plan ?? 'enterprise').toUpperCase(), bg: C.primaryFixed, fg: C.onPrimaryFixed, radius: 4, style: T.labelSm.copyWith(fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Account',
            offset: const Offset(0, 44),
            onSelected: (v) {
              if (v == 'tenant') {
                state.selectTenant(null);
              } else if (v == 'signout') {
                authRepo.signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(Env.offline ? 'Offline demo mode' : (sb.auth.currentUser?.email ?? ''), style: T.bodySm)),
              const PopupMenuItem(value: 'tenant', child: Text('Switch company')),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
            child: Avatar(url: state.avatarUrl, name: state.displayName),
          ),
        ]),
      ),
    );
  }
}
