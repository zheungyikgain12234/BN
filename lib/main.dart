import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_router.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.configured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    await authRepo.restore(); // a session left over from a reload must still match a company
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
