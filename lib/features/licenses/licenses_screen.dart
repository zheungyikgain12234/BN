import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../data/reseller_repository.dart';
import '../software/software_widgets.dart';

/// Licenses the company has purchased, with assigned / unassigned totals. Every reseller can assign them to clients
/// at their own selling price; only reseller admins can buy.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

enum _Filter { all, assigned, unassigned }

class _LicensesScreenState extends State<LicensesScreen> {
  List<License>? _licenses;
  List<Client> _clients = const [];
  Object? _error;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tenant = AppState.instance.tenant;
    if (tenant == null) {
      setState(() => _licenses = const []);
      return;
    }
    setState(() => _error = null);
    try {
      final results = await Future.wait([resellerRepo.licenses(tenant.id), resellerRepo.clients()]);
      if (mounted) {
        setState(() {
          _licenses = results[0] as List<License>;
          _clients = results[1] as List<Client>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _assign(License l) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _AssignDialog(license: l, clients: _clients));
    if (saved == true) _load();
  }

  Future<void> _unassign(License l) async {
    try {
      await resellerRepo.assign(l.id, null, null);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _stat(String label, int value, IconData icon, Color color) => Expanded(
        child: AppCard(
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: T.headlineLg),
              Text(label, style: T.labelSm.copyWith(color: C.secondary)),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final all = _licenses;
    final canAssign = AppState.instance.canManageCatalog;
    final assigned = all?.where((l) => l.assigned).length ?? 0;
    final rows = all == null
        ? const <License>[]
        : switch (_filter) {
            _Filter.all => all,
            _Filter.assigned => all.where((l) => l.assigned).toList(),
            _Filter.unassigned => all.where((l) => !l.assigned).toList(),
          };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Purchased licenses', style: T.headlineLg),
        const SizedBox(height: 12),
        if (all != null)
          Row(children: [
            _stat('Total licenses', all.length, Icons.key_outlined, C.primary),
            const SizedBox(width: 12),
            _stat('Assigned', assigned, Icons.assignment_turned_in_outlined, C.tertiary),
            const SizedBox(width: 12),
            _stat('Not yet assigned', all.length - assigned, Icons.pending_actions_outlined, C.amber),
          ]),
        const SizedBox(height: 12),
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : all == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<License>(
                      rows: rows,
                      searchHint: 'Search licenses',
                      emptyLabel: 'No licenses here yet.',
                      searchText: (l) => '${l.product.name} ${l.clientName}',
                      toolbar: [
                        SegmentedButton<_Filter>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: _Filter.all, label: Text('All')),
                            ButtonSegment(value: _Filter.assigned, label: Text('Assigned')),
                            ButtonSegment(value: _Filter.unassigned, label: Text('Unassigned')),
                          ],
                          selected: {_filter},
                          onSelectionChanged: (s) => setState(() => _filter = s.first),
                        ),
                      ],
                      columns: [
                        TableCol(
                          label: 'Software',
                          sortValue: (l) => l.product.name.toLowerCase(),
                          cell: (l) => Row(mainAxisSize: MainAxisSize.min, children: [
                            AppIconTile(product: l.product, size: 36),
                            const SizedBox(width: 10),
                            Flexible(child: Text(l.product.name, style: T.labelLg, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                        TableCol(label: 'Purchased', sortValue: (l) => l.purchasedAt, cell: (l) => Text(formatDate(l.purchasedAt))),
                        TableCol(label: 'Cost', numeric: true, sortValue: (l) => l.unitPrice, cell: (l) => Text(money(l.unitPrice, l.currency))),
                        TableCol(
                          label: 'Client',
                          sortValue: (l) => l.clientName.toLowerCase(),
                          cell: (l) => l.assigned ? Text(l.clientName.isEmpty ? '—' : l.clientName) : const Pill('Unassigned', bg: Color(0xFFFDEFC8), fg: Color(0xFF7A5200)),
                        ),
                        TableCol(label: 'Sold at', numeric: true, sortValue: (l) => l.sellPrice ?? -1, cell: (l) => Text(l.sellPrice == null ? '—' : money(l.sellPrice!, l.currency))),
                        TableCol(
                          label: 'Profit',
                          numeric: true,
                          sortValue: (l) => l.profit ?? -1e12,
                          cell: (l) => Text(l.profit == null ? '—' : money(l.profit!, l.currency), style: T.labelLg.copyWith(color: (l.profit ?? 0) >= 0 ? C.tertiary : C.error)),
                        ),
                      ],
                      actions: canAssign
                          ? (l) => [
                                IconButton(
                                  tooltip: l.assigned ? 'Change client / price' : 'Assign to client',
                                  icon: Icon(l.assigned ? Icons.edit_outlined : Icons.person_add_alt_1_outlined, size: 20),
                                  onPressed: () => _assign(l),
                                ),
                                if (l.assigned) IconButton(tooltip: 'Unassign', icon: const Icon(Icons.link_off, size: 20, color: C.error), onPressed: () => _unassign(l)),
                              ]
                          : null,
                    ),
        ),
      ]),
    );
  }
}

/// Pick a client and set the selling price (defaults to the catalogue price; anything on top is the reseller's profit).
class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.license, required this.clients});
  final License license;
  final List<Client> clients;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _form = GlobalKey<FormState>();
  late String? _clientId = widget.license.clientId;
  late final _price = TextEditingController(text: (widget.license.sellPrice ?? widget.license.unitPrice).toStringAsFixed(2));
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await resellerRepo.assign(widget.license.id, _clientId, double.parse(_price.text.trim()));
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
    final l = widget.license;
    final sell = double.tryParse(_price.text.trim());
    return AlertDialog(
      title: Text('Assign ${l.product.name}'),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.clients.isEmpty)
              Text('You have no clients yet. Add one on the Clients page first.', style: T.bodyMd.copyWith(color: C.error))
            else
              LabeledField(
                label: 'Client',
                required: true,
                child: DropdownButtonFormField<String>(
                  initialValue: _clientId,
                  isExpanded: true,
                  hint: dropdownHint('Select a client'),
                  decoration: fieldDecoration(),
                  items: [for (final c in widget.clients) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _clientId = v),
                  validator: (v) => v == null ? 'Select a client' : null,
                ),
              ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Selling price${l.currency.isEmpty ? '' : ' (${l.currency})'}',
              required: true,
              helper: 'Your cost: ${money(l.unitPrice, l.currency)}',
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration(),
                onChanged: (_) => setState(() {}),
                validator: (v) => double.tryParse((v ?? '').trim()) == null ? 'Enter a price' : null,
              ),
            ),
            if (sell != null) ...[
              const SizedBox(height: 10),
              Text('Your profit: ${money(sell - l.unitPrice, l.currency)}', style: T.labelLg.copyWith(color: sell >= l.unitPrice ? C.tertiary : C.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving || widget.clients.isEmpty ? null : _save, child: Text(_saving ? 'Saving...' : 'Assign')),
      ],
    );
  }
}
