import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';

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
  bool _remember = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action(); // router redirect takes over once the session changes
    } on AuthException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _run(() => authRepo.signIn(_email.text, _password.text));
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showError(context, 'Enter your business email first.');
      return;
    }
    await _run(() => authRepo.resetPassword(email));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent.')));
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
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: C.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 4))],
                ),
                child: const Icon(Icons.hub, color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Pill('Multi-Tenant Cloud Reseller Platform', icon: Icons.circle, fg: C.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Welcome to BizNest Hub', style: T.headlineLg, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Sign in to access your reseller & cloud software console',
                style: T.bodyMd.copyWith(color: C.secondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Business Email Address', style: T.labelMd),
              Text('Work domain required', style: T.labelSm.copyWith(color: C.secondary)),
            ]),
            const SizedBox(height: 6),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: fieldDecoration(hint: 'admin@reseller.gaincity.com', prefix: Icons.alternate_email),
              validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Password', style: T.labelMd),
              InkWell(onTap: _forgot, child: Text('Forgot password?', style: T.labelSm.copyWith(color: C.primary))),
            ]),
            const SizedBox(height: 6),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: fieldDecoration(
                hint: '••••••••••••',
                prefix: Icons.lock_outline,
                suffix: IconButton(
                  tooltip: 'Toggle password visibility',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: C.secondary),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false), activeColor: C.primary),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Remember my device for 30 days', style: T.bodySm.copyWith(color: C.secondary))),
              Pill('SSO Enforced', icon: Icons.badge_outlined, bg: C.surfaceLow, fg: C.tertiary, radius: 4, style: T.labelSm),
            ]),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Sign In to Console', icon: Icons.arrow_forward, loading: _loading, onPressed: _submit),
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('OR AUTHENTICATE VIA', style: T.labelSm.copyWith(color: C.secondary, letterSpacing: 0.8)),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 16),
            _SsoButton(
              label: 'Sign in with Microsoft 365 / Entra ID',
              leading: const _MicrosoftLogo(),
              onTap: _loading ? null : () => _run(() => authRepo.signInWithProvider(OAuthProvider.azure)),
            ),
            const SizedBox(height: 12),
            _SsoButton(
              label: 'Sign in with Google Workspace',
              leading: const _GoogleG(),
              onTap: _loading ? null : () => _run(() => authRepo.signInWithProvider(OAuthProvider.google)),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Don't have an account? ", style: T.bodySm.copyWith(color: C.secondary)),
              InkWell(onTap: () => context.go(Routes.register), child: Text('Create one', style: T.labelSm.copyWith(color: C.primary))),
            ]),
            const SizedBox(height: 24),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: const [
              Pill('SOC 2 Type II', icon: Icons.verified_user_outlined, fg: C.tertiary),
              Pill('ISO 27001', icon: Icons.lock_outline, fg: C.primary),
              Pill('GDPR Ready', icon: Icons.check_circle_outline, fg: C.tertiary),
            ]),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
              for (final l in const ['Enterprise Terms', 'Privacy Notice', 'Tenant Trust Hub'])
                Text(l, style: T.bodySm.copyWith(color: C.secondary)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SsoButton extends StatelessWidget {
  const _SsoButton({required this.label, required this.leading, this.onTap});
  final String label;
  final Widget leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              leading,
              const SizedBox(width: 12),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: T.labelLg)),
            ]),
          ),
        ),
      );
}

class _MicrosoftLogo extends StatelessWidget {
  const _MicrosoftLogo();

  @override
  Widget build(BuildContext context) {
    Widget sq(Color c) => Container(width: 9, height: 9, color: c);
    return SizedBox(
      width: 20,
      height: 20,
      child: Wrap(spacing: 1.5, runSpacing: 1.5, children: [
        sq(const Color(0xFFF25022)),
        sq(const Color(0xFF7FBA00)),
        sq(const Color(0xFF00A4EF)),
        sq(const Color(0xFFFFB900)),
      ]),
    );
  }
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)],
        ).createShader(r),
        child: const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
      );
}
