import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Second screen, shown after a successful sign-in: the companies this user belongs to.
class CompanySelectScreen extends StatefulWidget {
  const CompanySelectScreen({super.key});

  @override
  State<CompanySelectScreen> createState() => _CompanySelectScreenState();
}

class _CompanySelectScreenState extends State<CompanySelectScreen> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final all = app.companies;
    final q = _filter.text.trim().toLowerCase();
    final shown = all.where((t) => t.name.toLowerCase().contains(q)).toList();
    final email = sb.auth.currentUser?.email ?? '';
    return AuthScaffold(
      maxWidth: 460,
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
          Text('Select your company', style: T.headlineLg, textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(
            all.length == 1 ? 'Your account belongs to this company.' : 'Your account belongs to ${all.length} companies. Choose where to work.',
            style: T.bodyMd.copyWith(color: C.secondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (all.length > 5) ...[
            TextField(controller: _filter, onChanged: (_) => setState(() {}), decoration: fieldDecoration(hint: 'Search companies', prefix: Icons.search)),
            const SizedBox(height: 10),
          ],
          if (all.isEmpty)
            _note('No companies yet', 'You are a super admin and no company exists. Continue to add the first one.')
          else if (shown.isEmpty)
            _note('No match', 'No company matches "${_filter.text.trim()}".')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CompanyTile(company: shown[i], onTap: () => app.selectTenant(shown[i])),
              ),
            ),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: Text('Signed in as $email  •  ', overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.secondary))),
            InkWell(onTap: authRepo.signOut, child: Text('Sign out', style: T.labelSm.copyWith(color: C.primary))),
          ]),
        ],
      ),
    );
  }

  Widget _note(String title, String body) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          const Icon(Icons.business_outlined, size: 28, color: C.outline),
          const SizedBox(height: 6),
          Text(title, style: T.headlineSm),
          const SizedBox(height: 2),
          Text(body, style: T.bodySm.copyWith(color: C.onSurfaceVariant), textAlign: TextAlign.center),
        ]),
      );
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company, required this.onTap});
  final Tenant company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: C.surfaceLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: C.surfaceHigh,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(8)),
                child: Text(company.initials, style: T.labelMd.copyWith(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(company.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.labelLg),
                  Text(roleLabel(company.role), style: T.labelSm.copyWith(color: C.secondary)),
                ]),
              ),
              const Icon(Icons.arrow_forward, size: 18, color: C.outline),
            ]),
          ),
        ),
      );
}
