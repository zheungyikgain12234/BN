import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../core/config.dart';
import 'repository.dart';

/// Parent domain shared by the app (app.biznesthub.net) and the panel (cp.biznesthub.net).
/// Cookies set on it are sent to the panel, which is what makes the iframe already logged in.
const _cookieDomain = String.fromEnvironment('PANEL_COOKIE_DOMAIN', defaultValue: 'biznesthub.net');

const _flags = 'domain=$_cookieDomain; path=/; secure; samesite=none';

/// Last SSO outcome, shown on the Domain Search screen while debugging.
final ssoStatus = ValueNotifier<String>('SSO: not run yet');

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
      ssoStatus.value = 'SSO ok: server sent ${names.join(', ')}; browser kept ${kept.isEmpty ? 'none' : kept.join(', ')} (domain=$_cookieDomain, host=${web.window.location.host})';
    } else {
      ssoStatus.value = 'SSO failed: ${data?['reason'] ?? res.data}';
    }
  } catch (e) {
    ssoStatus.value = 'SSO error: $e';
  }
  return panelUrl;
}

/// Drops the panel session so the next user on this browser doesn't inherit it.
void clearStackcpSession() {
  web.document.cookie = 'PHPSESSID=; $_flags; max-age=0';
}
