import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
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
  List<Tenant>? _companies;
  Object? _companiesError;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _companiesError = null);
    try {
      final list = await tenantRepo.companies();
      if (!mounted) return;
      setState(() {
        _companies = list;

      });
    } catch (e) {
      if (mounted) setState(() => _companiesError = e);
    }
  }

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
      final signedIn = await authRepo.signUp(fullName: _name.text, email: _email.text, password: _password.text, companyId: _companyId!);
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
      maxWidth: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create your account', style: T.headlineLg, textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text('Register to access your console', style: T.bodyMd.copyWith(color: C.secondary), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Company',
              required: true,
              child: _companiesError != null
                  ? ErrorRetry(error: _companiesError!, onRetry: _loadCompanies)
                  : DropdownButtonFormField<String>(
                      initialValue: _companyId,
                      isExpanded: true,
                      decoration: fieldDecoration(),
                      hint: dropdownHint(_companies == null ? 'Loading companies...' : 'Select your company'),
                      items: [for (final t in _companies ?? const <Tenant>[]) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _companyId = v),
                      validator: (v) => v == null ? 'Select your company' : null,
                    ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Full Name',
              required: true,
              child: TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: fieldDecoration(hint: 'Jane Tan'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Email',
              required: true,
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: fieldDecoration(hint: 'jane.tan@company.com'),
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: fieldDecoration(
                  hint: 'At least 8 characters',
                  suffix: IconButton(
                    tooltip: 'Toggle password visibility',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: C.secondary),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Confirm Password',
              required: true,
              child: TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                decoration: fieldDecoration(hint: 'Repeat your password'),
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(label: 'Create account', icon: Icons.arrow_forward, loading: _loading, onPressed: _submit),
            const SizedBox(height: 14),
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
