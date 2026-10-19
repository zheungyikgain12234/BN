import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';

/// First screen: email + password. The company is chosen afterwards from the user's own companies.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await authRepo.signIn(email: _email.text, password: _password.text); // router redirect takes over
    } on AuthException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      maxWidth: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.hub, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(height: 12),
            Text('Welcome to BizNest Hub', style: T.headlineLg, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text('Sign in to your account', style: T.bodyMd.copyWith(color: C.secondary), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            LabeledField(
              label: 'Email',
              required: true,
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: fieldDecoration(hint: 'name@company.com'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Password',
              required: true,
              child: TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: fieldDecoration(
                  hint: 'Your password',
                  suffix: IconButton(
                    tooltip: 'Toggle password visibility',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: C.secondary),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Sign in', icon: Icons.arrow_forward, loading: _loading, onPressed: _submit),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Don't have an account? ", style: T.bodySm.copyWith(color: C.secondary)),
              InkWell(onTap: () => context.go(Routes.register), child: Text('Create one', style: T.labelSm.copyWith(color: C.primary))),
            ]),
          ],
        ),
      ),
    );
  }
}
