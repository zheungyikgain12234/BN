import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../app_router.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
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

/// Sidebar groups for the signed-in user's role: everyone browses; company admins also manage software;
/// super admins also manage companies and users.
List<_NavGroup> _navFor(AppState s) => [
      const _NavGroup('Hosting Solutions', [
        _NavItem('Domain Search', Icons.language, Routes.domainSearch),
        _NavItem('Domain Search (API)', Icons.travel_explore, Routes.domainSearchApi),
        _NavItem('VPS', Icons.dns_outlined, Routes.orderVps),
        _NavItem('Web Hosting', Icons.cloud_outlined, Routes.orderHosting),
        _NavItem('SSL Certificates', Icons.lock_outline, Routes.orderSsl),
        _NavItem('WordPress Hosting', Icons.web, Routes.orderWordpress),
      ]),
      const _NavGroup('Software Solutions', [
        _NavItem('Software', Icons.apps, Routes.software),
        _NavItem('Purchased Licenses', Icons.key_outlined, Routes.licenses),
      ]),
      const _NavGroup('Reseller', [
        _NavItem('Clients', Icons.groups_outlined, Routes.clients),
      ]),
      if (s.canManageCatalog)
        _NavGroup('Administration', [
          const _NavItem('Manage software', Icons.library_add_outlined, Routes.adminSoftware),
          if (s.isSuperAdmin) const _NavItem('Master Data', Icons.tune, Routes.adminMasters),
          if (s.isSuperAdmin) const _NavItem('Manage Companies', Icons.business_outlined, Routes.adminCompanies),
          if (s.canBuy) const _NavItem('Manage Users', Icons.manage_accounts_outlined, Routes.adminUsers),
        ]),
    ];

/// Top bar + left sidebar used by every post-login screen. Sidebar collapses to a drawer on narrow widths.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  bool _isActive(_NavItem i) {
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
        appBar: PreferredSize(preferredSize: const Size.fromHeight(60), child: _TopBar(width: c.maxWidth, showMenu: !wide)),
        drawer: wide ? null : Drawer(width: 280, backgroundColor: C.surfaceLow, child: SafeArea(child: sidebar)),
        body: Row(children: [
          if (wide) SizedBox(width: 232, child: ColoredBox(color: C.surfaceLow, child: sidebar)),
          Expanded(child: child),
        ]),
      );
    });
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({required this.isActive, required this.onSelect});
  final bool Function(_NavItem) isActive;
  final ValueChanged<String> onSelect;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final onSelect = widget.onSelect;
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final g in _navFor(AppState.instance)) ...[
            if (g.title != null)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _collapsed.contains(g.title) ? _collapsed.remove(g.title) : _collapsed.add(g.title!)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
                  child: Row(children: [
                    Expanded(child: Text(g.title!.toUpperCase(), style: T.labelSm.copyWith(color: C.secondary, fontWeight: FontWeight.w600, letterSpacing: 0.9))),
                    Icon(_collapsed.contains(g.title) ? Icons.expand_more : Icons.expand_less, size: 18, color: C.secondary),
                  ]),
                ),
              ),
            if (!_collapsed.contains(g.title))
              for (final i in g.items) _NavTile(item: i, active: isActive(i), onTap: () => onSelect(i.path)),
          ],
        ],
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(item.icon, size: 18, color: fg),
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
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.outlineVariant)), boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 1))]),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          if (showMenu)
            Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu, color: C.onSurfaceVariant), onPressed: () => Scaffold.of(ctx).openDrawer())),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.hub, size: 18, color: Colors.white),
          ),
          if (width >= 480) ...[
            const SizedBox(width: 12),
            Text('BizNest Hub', style: T.headlineSm.copyWith(fontWeight: FontWeight.w700)),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: ListenableBuilder(
              listenable: state,
              builder: (_, _) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (state.isSuperAdmin) const Pill('Admin portal', icon: Icons.admin_panel_settings_outlined, bg: C.primary, fg: Colors.white),
                  if (state.isSuperAdmin && state.tenant != null) const SizedBox(width: 6),
                  if (state.tenant != null)
                    Pill('Reseller portal · ${state.tenant!.name}', icon: Icons.storefront_outlined, bg: C.primaryFixed, fg: C.onPrimaryFixed),
                ]),
              ),
            ),
          ),
          const _CartButton(),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Account',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _openAccountMenu(context),
              child: Avatar(url: state.avatarUrl, name: state.displayName),
            ),
          ),
        ]),
      ),
    );
  }

  /// Custom menu instead of PopupMenuButton: a full-screen PointerInterceptor layer keeps the embedded
  /// iframe from swallowing any click (items, padding or outside-tap dismiss) while the menu is open.
  void _openAccountMenu(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Close menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (ctx, _, _) => Stack(children: [
        Positioned.fill(
          child: PointerInterceptor(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => Navigator.of(ctx).pop()),
          ),
        ),
        Positioned(
          top: 56,
          right: 16,
          // Interceptor wraps the whole card so its platform-view layer matches the full clickable box.
          child: PointerInterceptor(
            child: Material(
              color: C.surfaceLowest,
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 240,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Env.offline ? 'Offline demo mode' : (sb.auth.currentUser?.email ?? ''), style: T.bodySm.copyWith(color: C.secondary), overflow: TextOverflow.ellipsis),
                      if (AppState.instance.tenant != null) ...[
                        const SizedBox(height: 4),
                        Text(AppState.instance.tenant!.name, style: T.labelLg, overflow: TextOverflow.ellipsis),
                      ],
                    ]),
                  ),
                  const Divider(height: 1),
                  if (AppState.instance.companies.length > 1 || AppState.instance.isSuperAdmin)
                    InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        AppState.instance.switchCompany();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: const Row(children: [
                          Icon(Icons.swap_horiz, size: 18, color: C.onSurfaceVariant),
                          SizedBox(width: 12),
                          Text('Switch company'),
                        ]),
                      ),
                    ),
                  InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      authRepo.signOut();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: const Row(children: [
                        Icon(Icons.logout, size: 18, color: C.onSurfaceVariant),
                        SizedBox(width: 12),
                        Text('Sign out'),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Cart icon with the item count; opens the cart page.
class _CartButton extends StatefulWidget {
  const _CartButton();

  @override
  State<_CartButton> createState() => _CartButtonState();
}

class _CartButtonState extends State<_CartButton> {
  @override
  void initState() {
    super.initState();
    if (!Env.offline) CartState.instance.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: CartState.instance,
        builder: (_, _) => IconButton(
          tooltip: 'My cart',
          onPressed: () => context.go(Routes.cart),
          icon: Badge(
            isLabelVisible: CartState.instance.count > 0,
            label: Text('${CartState.instance.count}'),
            child: const Icon(Icons.shopping_cart_outlined, color: C.onSurfaceVariant),
          ),
        ),
      );
}
