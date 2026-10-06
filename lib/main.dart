import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_router.dart';
import 'core/config.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.configured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }
  runApp(const BizNestApp());
}

class BizNestApp extends StatelessWidget {
  const BizNestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'BizNest Hub',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: router,
      );
}
