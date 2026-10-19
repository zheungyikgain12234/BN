import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final signedIn = await authRepo.signUp(fullName: _name.text, email: _email.text, password: _password.text);
      // With a session, the router redirect moves on by itself; otherwise email confirmation is pending.
      if (!signedIn && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. Check your email to confirm, then sign in.')),
        );
        context.go(Routes.login);
      }
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
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create your account', style: T.headlineLg, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Register to access your reseller & cloud software console',
                style: T.bodyMd.copyWith(color: C.secondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text('Full Name', style: T.labelMd),
            const SizedBox(height: 6),
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: fieldDecoration(hint: 'Jane Tan', prefix: Icons.person_outline),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 16),
            Text('Business Email Address', style: T.labelMd),
            const SizedBox(height: 6),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: fieldDecoration(hint: 'admin@reseller.gaincity.com', prefix: Icons.alternate_email),
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),
            Text('Password', style: T.labelMd),
            const SizedBox(height: 6),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: fieldDecoration(
                hint: 'At least 8 characters',
                prefix: Icons.lock_outline,
                suffix: IconButton(
                  tooltip: 'Toggle password visibility',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: C.secondary),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: 16),
            Text('Confirm Password', style: T.labelMd),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submit(),
              decoration: fieldDecoration(hint: 'Repeat password', prefix: Icons.lock_outline),
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Create Account', icon: Icons.arrow_forward, loading: _loading, onPressed: _submit),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Already have an account? ', style: T.bodySm.copyWith(color: C.secondary)),
              InkWell(onTap: () => context.go(Routes.login), child: Text('Sign in', style: T.labelSm.copyWith(color: C.primary))),
            ]),
          ],
        ),
      ),
    );
  }
}
