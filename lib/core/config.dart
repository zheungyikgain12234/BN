/// Defaults point at the Biznest Supabase project. Override with:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// (The publishable key is public by design; never put a service-role or secret key here.)
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://noomyjgwxiqevchvopjy.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_aAb6Tn2R_pNbUQOvljwoEw_DWe1EDOW');
  /// White-labelled hosting panel (embedded order pages and basket). Override: --dart-define=PANEL_BASE=https://cp.yourdomain.com
  static const panelBase = String.fromEnvironment('PANEL_BASE', defaultValue: 'https://cp.biznesthub.net');

  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// No Supabase credentials: run the UI only (no login, demo tenant, opens on Domain Search).
  static bool get offline => !configured;

  /// Where OAuth (Microsoft / Google) redirects back to on mobile/desktop.
  /// Add it to Supabase Auth > URL Configuration. Ignored on web.
  static const oauthRedirect = String.fromEnvironment('OAUTH_REDIRECT', defaultValue: 'com.biznest://login-callback/');
}
