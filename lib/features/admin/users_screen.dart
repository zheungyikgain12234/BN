import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/admin_repository.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Admin: create, edit, suspend and delete users. A user can belong to several companies.
/// Super admins manage every user; company admins manage users of the companies they administer.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<ManagedUser>? _users;
  List<Tenant> _companies = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Companies first, so Add user still knows them if the users call fails.
      final app = AppState.instance;
      final companies = app.isSuperAdmin ? await adminRepo.companies() : app.companies.where((c) => c.role == roleCompanyAdmin).toList();
      if (mounted) setState(() => _companies = companies);
      final users = await adminRepo.users();
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _companyName(String id) => _companies.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? 'Unknown company';

  String _companiesText(ManagedUser u) => u.memberships.map((m) => _companyName(m.companyId)).join(', ');

  Future<void> _edit([ManagedUser? u]) async {
    if (_companies.isEmpty) {
      showError(context, 'There is no company to add users to.');
      return;
    }
    final saved = await showDialog<bool>(context: context, builder: (_) => _UserDialog(user: u, companies: _companies));
    if (saved == true) _load();
  }

  Future<void> _delete(ManagedUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(u.canEditAccount
            ? '${u.email} will be permanently deleted and can no longer sign in.'
            : '${u.email} also belongs to other companies, so they will only be removed from your company.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(u.canEditAccount ? 'Delete' : 'Remove', style: const TextStyle(color: C.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await adminRepo.deleteUser(u.id);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleSuspend(ManagedUser u) async {
    try {
      await adminRepo.updateUser(u.id, suspended: !u.suspended);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Users', style: T.headlineLg),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : _users == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<ManagedUser>(
                      rows: _users!,
                      searchHint: 'Search users',
                      emptyLabel: 'No users yet.',
                      searchText: (u) => '${u.fullName} ${u.email} ${_companiesText(u)}',
                      toolbar: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add user'))],
                      columns: [
                        TableCol(
                          label: 'User',
                          sortValue: (u) => (u.fullName.isEmpty ? u.email : u.fullName).toLowerCase(),
                          cell: (u) => Row(mainAxisSize: MainAxisSize.min, children: [
                            Avatar(name: u.fullName.isEmpty ? u.email : u.fullName, size: 30),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(u.fullName.isEmpty ? u.email : u.fullName, style: T.labelLg, overflow: TextOverflow.ellipsis),
                                if (u.fullName.isNotEmpty) Text(u.email, style: T.bodySm.copyWith(color: C.secondary), overflow: TextOverflow.ellipsis),
                              ]),
                            ),
                          ]),
                        ),
                        TableCol(
                          label: 'Companies',
                          sortValue: (u) => _companiesText(u).toLowerCase(),
                          cell: (u) => u.memberships.isEmpty
                              ? const Text('—')
                              : Wrap(spacing: 6, runSpacing: 4, children: [
                                  for (final m in u.memberships)
                                    Pill('${_companyName(m.companyId)} · ${roleLabel(m.role)}', bg: m.role == roleCompanyAdmin ? C.primaryFixed : C.surfaceContainer, fg: m.role == roleCompanyAdmin ? C.onPrimaryFixed : C.onSurfaceVariant, radius: 4),
                                ]),
                        ),
                        TableCol(
                          label: 'Status',
                          sortValue: (u) => u.suspended ? 1 : 0,
                          cell: (u) => u.isAdmin
                              ? const Pill('Super admin', bg: C.primaryFixed, fg: C.onPrimaryFixed, radius: 4)
                              : u.suspended
                                  ? const Pill('Suspended', bg: C.errorContainer, fg: C.error, radius: 4)
                                  : const Pill('Active', bg: C.tertiaryFixed, fg: C.onTertiaryFixedVariant, radius: 4),
                        ),
                        TableCol(
                          label: 'Last sign-in',
                          sortValue: (u) => u.lastSignIn?.millisecondsSinceEpoch ?? 0,
                          cell: (u) => Text(u.lastSignIn == null ? 'Never' : formatDate(u.lastSignIn!)),
                        ),
                      ],
                      actions: (u) => [
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(u)),
                        if (u.id != me) ...[
                          if (u.canEditAccount)
                            IconButton(
                              tooltip: u.suspended ? 'Reactivate' : 'Suspend',
                              icon: Icon(u.suspended ? Icons.lock_open : Icons.block, size: 18, color: C.secondary),
                              onPressed: () => _toggleSuspend(u),
                            ),
                          IconButton(
                            tooltip: u.canEditAccount ? 'Delete' : 'Remove from company',
                            icon: const Icon(Icons.delete_outline, size: 18, color: C.error),
                            onPressed: () => _delete(u),
                          ),
                        ],
                      ],
                    ),
        ),
      ]),
    );
  }
}

/// One editable company + role row in the user form.
class _MembershipDraft {
  _MembershipDraft(this.companyId, this.role);
  String? companyId;
  String role;
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({this.user, required this.companies});
  final ManagedUser? user;
  final List<Tenant> companies;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.fullName);
  late final _email = TextEditingController(text: widget.user?.email);
  final _password = TextEditingController();
  late final List<_MembershipDraft> _rows = [
    for (final m in widget.user?.memberships ?? const <Membership>[])
      if (widget.companies.any((c) => c.id == m.companyId)) _MembershipDraft(m.companyId, m.role),
    if (widget.user == null || (widget.user!.memberships.isEmpty)) _MembershipDraft(widget.companies.first.id, roleCustomer),
  ];
  bool _saving = false;

  bool get _isNew => widget.user == null;
  bool get _accountLocked => !_isNew && !widget.user!.canEditAccount;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  List<Membership> _memberships() => [for (final r in _rows) if (r.companyId != null) Membership(companyId: r.companyId!, role: r.role)];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final memberships = _memberships();
    if (memberships.isEmpty) {
      showError(context, 'Add at least one company.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isNew) {
        await adminRepo.createUser(email: _email.text, password: _password.text, fullName: _name.text, memberships: memberships);
      } else {
        await adminRepo.updateUser(
          widget.user!.id,
          fullName: _accountLocked ? null : _name.text,
          password: _accountLocked ? null : _password.text,
          memberships: memberships,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  void _addRow() {
    final used = _rows.map((r) => r.companyId).toSet();
    final next = widget.companies.where((c) => !used.contains(c.id)).firstOrNull;
    if (next != null) setState(() => _rows.add(_MembershipDraft(next.id, roleCustomer)));
  }

  Widget _membershipRow(int i) {
    final r = _rows[i];
    final taken = _rows.where((o) => o != r).map((o) => o.companyId).toSet();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: r.companyId,
            isExpanded: true,
            decoration: fieldDecoration(),
            hint: dropdownHint('Select a company'),
            items: [for (final c in widget.companies) if (!taken.contains(c.id)) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => r.companyId = v),
            validator: (v) => v == null ? 'Select a company' : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: r.role,
            isExpanded: true,
            decoration: fieldDecoration(),
            items: [for (final role in memberRoles) DropdownMenuItem(value: role, child: Text(roleLabel(role), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => r.role = v ?? r.role),
          ),
        ),
        IconButton(
          tooltip: 'Remove company',
          icon: const Icon(Icons.close, size: 18),
          onPressed: _rows.length <= 1 ? null : () => setState(() => _rows.removeAt(i)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = _rows.length < widget.companies.length;
    return AlertDialog(
      title: Text(_isNew ? 'Add user' : 'Edit user'),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_accountLocked) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(8)),
                child: Text('This user also belongs to other companies, so only their access to your companies can be changed.', style: T.bodySm.copyWith(color: C.secondary)),
              ),
              const SizedBox(height: 12),
            ],
            LabeledField(label: 'Full Name', child: TextFormField(controller: _name, enabled: !_accountLocked, decoration: fieldDecoration(hint: 'Jane Tan'))),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Email',
              required: true,
              child: TextFormField(
                controller: _email,
                enabled: _isNew, // the email is the login; changing it isn't supported here
                keyboardType: TextInputType.emailAddress,
                decoration: fieldDecoration(hint: 'jane.tan@company.com'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: _isNew ? 'Password' : 'New Password',
              required: _isNew,
              helper: _isNew ? null : 'Leave blank to keep the current password.',
              child: TextFormField(
                controller: _password,
                enabled: !_accountLocked,
                obscureText: true,
                decoration: fieldDecoration(hint: 'At least 8 characters'),
                validator: (v) {
                  if (!_isNew && (v == null || v.isEmpty)) return null;
                  return (v == null || v.length < 8) ? 'Use at least 8 characters' : null;
                },
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Companies and roles',
              required: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < _rows.length; i++) _membershipRow(i),
                TextButton.icon(onPressed: canAddMore ? _addRow : null, icon: const Icon(Icons.add, size: 16), label: const Text('Add company')),
              ]),
            ),
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
