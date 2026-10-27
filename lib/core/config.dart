/// Supabase credentials come from supabase.env.json (git-ignored; copy supabase.env.example.json):
/// flutter run --dart-define-from-file=supabase.env.json
/// flutter build web --dart-define-from-file=supabase.env.json
/// Without it the app runs offline (UI only). Never put a service-role or secret key in that file.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  /// White-labelled hosting panel (embedded order pages and basket). Override: --dart-define=PANEL_BASE=https://cp.yourdomain.com
  static const panelBase = String.fromEnvironment('PANEL_BASE', defaultValue: 'https://cp.biznesthub.net');

  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// No Supabase credentials: run the UI only (no login, demo tenant, opens on Domain Search).
  static bool get offline => !configured;

  /// Where OAuth (Microsoft / Google) redirects back to on mobile/desktop.
  /// Add it to Supabase Auth > URL Configuration. Ignored on web.
  static const oauthRedirect = String.fromEnvironment('OAUTH_REDIRECT', defaultValue: 'com.biznest://login-callback/');
}
