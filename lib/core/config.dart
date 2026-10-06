/// Supply with: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get configured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// No Supabase credentials: run the UI only (no login, demo tenant, opens on Domain Search).
  static bool get offline => !configured;

  /// Where OAuth (Microsoft / Google) redirects back to on mobile/desktop.
  /// Add it to Supabase Auth > URL Configuration. Ignored on web.
  static const oauthRedirect = String.fromEnvironment('OAUTH_REDIRECT', defaultValue: 'com.biznest://login-callback/');
}
