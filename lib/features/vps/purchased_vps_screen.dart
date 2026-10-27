import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../data/reseller_repository.dart';

/// VPS servers the company has bought, with assigned / unassigned totals. Like Purchased Licenses, Domains and Hosting: the
/// reseller assigns each server to a client at their own selling price, and the difference to what they paid is their profit.
class PurchasedVpsScreen extends StatefulWidget {
  const PurchasedVpsScreen({super.key});

  @override
  State<PurchasedVpsScreen> createState() => _PurchasedVpsScreenState();
}

enum _Filter { all, assigned, unassigned }

/// "dc_location-lhr" -> "UK", "dc_location-dfw" -> "USA"; anything else is shown as stored.
String _place(String code) => switch (code) {
      'dc_location-lhr' => 'UK',
      'dc_location-dfw' => 'USA',
      _ => code,
    };

class _PurchasedVpsScreenState extends State<PurchasedVpsScreen> {
  List<PurchasedVps>? _packages;
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
      setState(() => _packages = const []);
      return;
    }
    setState(() => _error = null);
    try {
      final results = await Future.wait([resellerRepo.purchasedVps(tenant.id), resellerRepo.clients()]);
      if (mounted) {
        setState(() {
          _packages = results[0] as List<PurchasedVps>;
          _clients = results[1] as List<Client>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _assign(PurchasedVps d) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _AssignDialog(vps: d, clients: _clients));
    if (saved == true) _load();
  }

  Future<void> _unassign(PurchasedVps d) async {
    try {
      await resellerRepo.assignVps(d.id, null, null);
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
    final all = _packages;
    final canAssign = AppState.instance.canManageCatalog;
    final assigned = all?.where((d) => d.assigned).length ?? 0;
    final rows = all == null
        ? const <PurchasedVps>[]
        : switch (_filter) {
            _Filter.all => all,
            _Filter.assigned => all.where((d) => d.assigned).toList(),
            _Filter.unassigned => all.where((d) => !d.assigned).toList(),
          };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Purchased VPS', style: T.headlineLg),
        const SizedBox(height: 12),
        if (all != null)
          Row(children: [
            _stat('Total servers', all.length, Icons.dns_outlined, C.primary),
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
                  : SortableTable<PurchasedVps>(
                      rows: rows,
                      searchHint: 'Search VPS',
                      emptyLabel: 'No VPS here yet. Buy a plan from VPS.',
                      searchText: (d) => '${d.planName} ${d.serverName} ${d.osLabel} ${d.clientName}',
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
                          label: 'Plan',
                          sortValue: (d) => d.planName.toLowerCase(),
                          cell: (d) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${d.planName} · ${d.serverName}', style: T.labelLg),
                            Text('${d.osLabel} · ${_place(d.location)}', style: T.bodySm.copyWith(color: C.secondary)),
                            if (d.failed) Text(d.note ?? 'VPS order failed', style: T.bodySm.copyWith(color: C.error), overflow: TextOverflow.ellipsis),
                            if (d.status == 'test_registered') Text('Sandbox: not ordered at 20i', style: T.bodySm.copyWith(color: C.secondary)),
                          ]),
                        ),
                        TableCol(label: 'Months', numeric: true, sortValue: (d) => d.months, cell: (d) => Text('${d.months}')),
                        TableCol(label: 'Purchased', sortValue: (d) => d.purchasedAt, cell: (d) => Text(formatDate(d.purchasedAt))),
                        TableCol(label: 'Cost', numeric: true, sortValue: (d) => d.unitPrice, cell: (d) => Text(money(d.unitPrice, d.currency))),
                        TableCol(
                          label: 'Client',
                          sortValue: (d) => d.clientName.toLowerCase(),
                          cell: (d) => d.assigned ? Text(d.clientName.isEmpty ? '—' : d.clientName) : const Pill('Unassigned', bg: Color(0xFFFDEFC8), fg: Color(0xFF7A5200)),
                        ),
                        TableCol(label: 'Sold at', numeric: true, sortValue: (d) => d.sellPrice ?? -1, cell: (d) => Text(d.sellPrice == null ? '—' : money(d.sellPrice!, d.currency))),
                        TableCol(
                          label: 'Profit',
                          numeric: true,
                          sortValue: (d) => d.profit ?? -1e12,
                          cell: (d) => Text(d.profit == null ? '—' : money(d.profit!, d.currency), style: T.labelLg.copyWith(color: (d.profit ?? 0) >= 0 ? C.tertiary : C.error)),
                        ),
                      ],
                      actions: canAssign
                          ? (d) => [
                                if (!d.failed)
                                  IconButton(
                                    tooltip: d.assigned ? 'Change client / price' : 'Assign to client',
                                    icon: Icon(d.assigned ? Icons.edit_outlined : Icons.person_add_alt_1_outlined, size: 20),
                                    onPressed: () => _assign(d),
                                  ),
                                if (d.assigned) IconButton(tooltip: 'Unassign', icon: const Icon(Icons.link_off, size: 20, color: C.error), onPressed: () => _unassign(d)),
                              ]
                          : null,
                    ),
        ),
      ]),
    );
  }
}

/// Pick a client and set the selling price (defaults to what the reseller paid; anything on top is their profit).
class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.vps, required this.clients});
  final PurchasedVps vps;
  final List<Client> clients;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _form = GlobalKey<FormState>();
  late String? _clientId = widget.vps.clientId;
  late final _price = TextEditingController(text: (widget.vps.sellPrice ?? widget.vps.unitPrice).toStringAsFixed(2));
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
      await resellerRepo.assignVps(widget.vps.id, _clientId, double.parse(_price.text.trim()));
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
    final d = widget.vps;
    final sell = double.tryParse(_price.text.trim());
    return AlertDialog(
      title: Text('Assign ${d.planName} (${d.serverName})'),
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
              label: 'Selling price${d.currency.isEmpty ? '' : ' (${d.currency})'}',
              required: true,
              helper: 'Your cost: ${money(d.unitPrice, d.currency)}',
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
              Text('Your profit: ${money(sell - d.unitPrice, d.currency)}', style: T.labelLg.copyWith(color: sell >= d.unitPrice ? C.tertiary : C.error)),
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
