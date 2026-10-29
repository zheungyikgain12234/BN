import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/config.dart';
import 'repository.dart';

/// Parent domain shared by the app (app.biznesthub.net) and the panel (cp.biznesthub.net).
/// Cookies set on it are sent to the panel, which is what makes the iframe already logged in.
const _cookieDomain = String.fromEnvironment('PANEL_COOKIE_DOMAIN', defaultValue: 'biznesthub.net');

const _flags = 'domain=$_cookieDomain; path=/; secure; samesite=none';

/// SSO outcome goes to the browser console (DevTools) rather than the UI.
void _log(String msg) => web.console.info(msg.toJS);

/// Logs the signed-in user into the panel (via the stackcp-sso Edge Function) and returns
/// [panelUrl] to load. If SSO isn't possible the user just sees the panel's normal login.
Future<String> stackcpUrl(String panelUrl) async {
  if (Env.offline || sb.auth.currentSession == null) return panelUrl;
  try {
    final res = await sb.functions.invoke('stackcp-sso');
    final data = res.data as Map?;
    if (data?['sso'] == true) {
      final names = <String>[];
      for (final c in (data!['cookies'] as List)) {
        web.document.cookie = '${c['name']}=${c['value']}; $_flags';
        names.add('${c['name']}');
      }
      final kept = names.where((n) => web.document.cookie.contains('$n=')).toList();
      _log('SSO ok: server sent ${names.join(', ')}; browser kept ${kept.isEmpty ? 'none' : kept.join(', ')} (domain=$_cookieDomain, host=${web.window.location.host})');
    } else {
      _log('SSO failed: ${data?['reason'] ?? res.data}');
    }
  } catch (e) {
    _log('SSO error: $e');
  }
  return panelUrl;
}

/// Adds domains to the panel's own basket (cp.biznesthub.net) and gives the browser that same panel session, so the
/// embedded basket shows them. `error` is null on success, otherwise why it failed; `ids` maps each domain to its item id
/// in the panel basket (needed to remove it later). Best effort: our own basket is the source of truth, this mirrors it.
Future<({String? error, Map<String, String> ids})> addDomainsToPanelBasket(List<({String name, int years, String tld, String currency, double price})> items) async {
  if (Env.offline || sb.auth.currentSession == null) return (error: 'not signed in', ids: <String, String>{});
  try {
    final res = await sb.functions.invoke('stackcp-sso', body: {
      'basket': [
        for (final i in items)
          {'name': i.name, 'productCode': 'domain:.${i.tld}', 'periodMonths': i.years * 12, 'currency': i.currency, 'price': i.price},
      ],
    });
    final data = res.data as Map?;
    if (data?['sso'] != true) return (error: '${data?['reason'] ?? 'panel login failed'}', ids: <String, String>{});
    for (final c in (data!['cookies'] as List)) {
      web.document.cookie = '${c['name']}=${c['value']}; $_flags';
    }
    final rows = (data['basket'] as List? ?? const []);
    final failed = [for (final r in rows) if (r['ok'] != true) '${r['name']}: ${r['detail']}'];
    final ids = {for (final r in rows) if (r['ok'] == true && r['id'] != null) '${r['name']}': '${r['id']}'};
    return (error: failed.isEmpty ? null : failed.join('; '), ids: ids);
  } catch (e) {
    return (error: '$e', ids: <String, String>{});
  }
}

/// Takes items out of the panel basket so it matches ours again. Returns null on success, otherwise why it failed.
Future<String?> removeFromPanelBasket(List<String> ids) async {
  if (ids.isEmpty) return null;
  if (Env.offline || sb.auth.currentSession == null) return 'not signed in';
  try {
    final res = await sb.functions.invoke('stackcp-sso', body: {'removeBasket': ids});
    final data = res.data as Map?;
    if (data?['sso'] != true) return '${data?['reason'] ?? 'panel login failed'}';
    final failed = [for (final r in (data!['removed'] as List? ?? const [])) if (r['ok'] != true) '${r['detail']}'];
    return failed.isEmpty ? null : failed.join('; ');
  } catch (e) {
    return '$e';
  }
}

/// Drops the panel session so the next user on this browser doesn't inherit it.
void clearStackcpSession() {
  web.document.cookie = 'PHPSESSID=; $_flags; max-age=0';
}
