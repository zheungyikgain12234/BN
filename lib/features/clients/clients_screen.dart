import 'package:flutter/material.dart';

import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../data/reseller_repository.dart';

/// A reseller company's own clients (private to the company).
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Client>? _clients;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await resellerRepo.clients();
      if (mounted) setState(() => _clients = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Client? c]) async {
    if (AppState.instance.tenant == null) {
      showError(context, 'Pick a company first (Switch company) to manage its clients.');
      return;
    }
    final saved = await showDialog<bool>(context: context, builder: (_) => _ClientDialog(client: c));
    if (saved == true) _load();
  }

  Future<void> _delete(Client c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove client?'),
        content: Text('"${c.name}" will be removed. Licenses assigned to them become unassigned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: C.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await resellerRepo.deleteClient(c.id);
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
        Text('Clients', style: T.headlineLg),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : _clients == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<Client>(
                      rows: _clients!,
                      searchHint: 'Search clients',
                      emptyLabel: 'No clients yet. Add your first client.',
                      searchText: (c) => '${c.name} ${c.contactName} ${c.email} ${c.phone}',
                      toolbar: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: const Text('Add client'))],
                      columns: [
                        TableCol(label: 'Client', sortValue: (c) => c.name.toLowerCase(), cell: (c) => Text(c.name, style: T.labelLg)),
                        TableCol(label: 'Contact', sortValue: (c) => c.contactName, cell: (c) => Text(c.contactName.isEmpty ? '—' : c.contactName)),
                        TableCol(label: 'Email', sortValue: (c) => c.email, cell: (c) => Text(c.email.isEmpty ? '—' : c.email)),
                        TableCol(label: 'Phone', sortValue: (c) => c.phone, cell: (c) => Text(c.phone.isEmpty ? '—' : c.phone)),
                      ],
                      actions: (c) => [
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(c)),
                        IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 20, color: C.error), onPressed: () => _delete(c)),
                      ],
                    ),
        ),
      ]),
    );
  }
}

class _ClientDialog extends StatefulWidget {
  const _ClientDialog({this.client});
  final Client? client;

  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client?.name);
  late final _contact = TextEditingController(text: widget.client?.contactName);
  late final _email = TextEditingController(text: widget.client?.email);
  late final _phone = TextEditingController(text: widget.client?.phone);
  late final _notes = TextEditingController(text: widget.client?.notes);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _email, _phone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await resellerRepo.saveClient(
        id: widget.client?.id,
        tenantId: AppState.instance.tenant!.id,
        name: _name.text,
        contactName: _contact.text,
        email: _email.text,
        phone: _phone.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.client == null ? 'Add client' : 'Edit client'),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LabeledField(
              label: 'Client name',
              required: true,
              child: TextFormField(controller: _name, decoration: fieldDecoration(hint: 'Acme Trading Pte Ltd'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Client name is required' : null),
            ),
            const SizedBox(height: 14),
            LabeledField(label: 'Contact person', child: TextFormField(controller: _contact, decoration: fieldDecoration())),
            const SizedBox(height: 14),
            LabeledField(label: 'Email', child: TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: fieldDecoration())),
            const SizedBox(height: 14),
            LabeledField(label: 'Phone', child: TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: fieldDecoration())),
            const SizedBox(height: 14),
            LabeledField(label: 'Notes', child: TextFormField(controller: _notes, maxLines: 3, decoration: fieldDecoration())),
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
