import 'package:flutter/material.dart';

import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/admin_repository.dart';
import '../../data/models.dart';

/// Admin: add, edit and remove the companies users can sign in to.
class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  List<Tenant>? _companies;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await adminRepo.companies();
      if (mounted) setState(() => _companies = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Tenant? t]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _CompanyDialog(company: t));
    if (saved == true) _load();
  }

  Future<void> _delete(Tenant t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove company?'),
        content: Text('"${t.name}" will be deleted and all of its users lose their company membership. '
            'Their accounts are kept; reassign them on the Users page.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: C.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await adminRepo.deleteCompany(t.id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Companies', style: T.headlineLg),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : _companies == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<Tenant>(
                      rows: _companies!,
                      searchHint: 'Search companies',
                      emptyLabel: 'No companies yet. Add the first one.',
                      searchText: (t) => '${t.name} ${t.code} ${t.domain} ${t.plan}',
                      toolbar: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: const Text('Add company'))],
                      columns: [
                        TableCol(label: 'Company', sortValue: (t) => t.name.toLowerCase(), cell: (t) => Text(t.name, style: T.labelLg)),
                        TableCol(label: 'Code', sortValue: (t) => t.code, cell: (t) => Text(t.code.isEmpty ? '—' : t.code)),
                        TableCol(label: 'Domain', sortValue: (t) => t.domain, cell: (t) => Text(t.domain.isEmpty ? '—' : t.domain)),
                        TableCol(label: 'Plan', sortValue: (t) => t.plan, cell: (t) => Pill(t.plan, bg: C.primaryFixed, fg: C.onPrimaryFixed, radius: 4)),
                        TableCol(label: 'Seats', numeric: true, sortValue: (t) => t.seats, cell: (t) => Text('${t.seats}')),
                      ],
                      actions: (t) => [
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(t)),
                        IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 20, color: C.error), onPressed: () => _delete(t)),
                      ],
                    ),
        ),
      ]),
    );
  }
}

class _CompanyDialog extends StatefulWidget {
  const _CompanyDialog({this.company});
  final Tenant? company;

  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.company?.name);
  late final _code = TextEditingController(text: widget.company?.code);
  late final _domain = TextEditingController(text: widget.company?.domain);
  late final _plan = TextEditingController(text: widget.company?.plan);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _domain.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await adminRepo.saveCompany(id: widget.company?.id, name: _name.text, code: _code.text, domain: _domain.text, plan: _plan.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e.toString().contains('tenants_name_key') ? 'A company with this name already exists.' : e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.company == null ? 'Add company' : 'Edit company'),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LabeledField(
              label: 'Company name',
              required: true,
              child: TextFormField(
                controller: _name,
                decoration: fieldDecoration(hint: 'Gain City Digital Innovation Pte Ltd'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Company name is required' : null,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(label: 'Code', child: TextFormField(controller: _code, decoration: fieldDecoration(hint: 'TEN-94820-SG'))),
            const SizedBox(height: 14),
            LabeledField(label: 'Domain', child: TextFormField(controller: _domain, decoration: fieldDecoration(hint: 'gaincity.com.sg'))),
            const SizedBox(height: 14),
            LabeledField(label: 'Plan', child: TextFormField(controller: _plan, decoration: fieldDecoration(hint: 'enterprise'))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
      ],
    );
  }
}
