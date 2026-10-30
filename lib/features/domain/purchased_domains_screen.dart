import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/repository.dart';
import '../../data/reseller_repository.dart';

/// Domains the company has bought, with assigned / unassigned totals. Like Purchased Licenses: the reseller assigns
/// each domain to a client at their own selling price, and the difference to what they paid is their profit.
class PurchasedDomainsScreen extends StatefulWidget {
  const PurchasedDomainsScreen({super.key});

  @override
  State<PurchasedDomainsScreen> createState() => _PurchasedDomainsScreenState();
}

enum _Filter { all, assigned, unassigned }

class _PurchasedDomainsScreenState extends State<PurchasedDomainsScreen> {
  List<PurchasedDomain>? _domains;
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
      setState(() => _domains = const []);
      return;
    }
    setState(() => _error = null);
    try {
      final results = await Future.wait([resellerRepo.purchasedDomains(tenant.id), resellerRepo.clients()]);
      if (mounted) {
        setState(() {
          _domains = results[0] as List<PurchasedDomain>;
          _clients = results[1] as List<Client>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _assign(PurchasedDomain d) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _AssignDialog(domain: d, clients: _clients));
    if (saved == true) _load();
  }

  Future<void> _unassign(PurchasedDomain d) async {
    try {
      await resellerRepo.assignDomain(d.id, null, null);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _domains;
    final canAssign = AppState.instance.canManageCatalog;
    final assigned = all?.where((d) => d.assigned).length ?? 0;
    final withProfit = all?.where((d) => d.profit != null).toList() ?? const <PurchasedDomain>[];
    final totalProfit = withProfit.fold<double>(0, (sum, d) => sum + d.profit!);
    final rows = all == null
        ? const <PurchasedDomain>[]
        : switch (_filter) {
            _Filter.all => all,
            _Filter.assigned => all.where((d) => d.assigned).toList(),
            _Filter.unassigned => all.where((d) => !d.assigned).toList(),
          };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Purchased domains', style: T.headlineLg),
        const SizedBox(height: 16),
        if (all != null)
          Row(children: [
            Expanded(
              child: _Entrance(
                index: 0,
                child: _StatCard(
                  label: 'Total domains',
                  value: all.length,
                  icon: Icons.language,
                  color: C.primary,
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Entrance(
                index: 1,
                child: _StatCard(
                  label: 'Assigned',
                  value: assigned,
                  icon: Icons.assignment_turned_in_outlined,
                  color: C.tertiary,
                  selected: _filter == _Filter.assigned,
                  onTap: () => setState(() => _filter = _Filter.assigned),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Entrance(
                index: 2,
                child: _StatCard(
                  label: 'Not yet assigned',
                  value: all.length - assigned,
                  icon: Icons.pending_actions_outlined,
                  color: const Color(0xFFB87503),
                  selected: _filter == _Filter.unassigned,
                  onTap: () => setState(() => _filter = _Filter.unassigned),
                ),
              ),
            ),
            if (withProfit.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _Entrance(
                  index: 3,
                  child: _StatCard(
                    label: 'Total profit',
                    amount: totalProfit,
                    currency: withProfit.first.currency,
                    icon: Icons.trending_up,
                    color: totalProfit >= 0 ? C.tertiary : C.error,
                  ),
                ),
              ),
            ],
          ]),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : all == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<PurchasedDomain>(
                      rows: rows,
                      searchHint: 'Search domains',
                      emptyLabel: 'No domains here yet. Buy one from Domain Search (API).',
                      searchText: (d) => '${d.domain} ${d.clientName}',
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
                          label: 'Domain',
                          sortValue: (d) => d.domain.toLowerCase(),
                          cell: (d) => Row(mainAxisSize: MainAxisSize.min, children: [
                            _DomainAvatar(failed: d.failed, assigned: d.assigned),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(d.domain, style: T.labelLg, overflow: TextOverflow.ellipsis),
                                if (d.failed) Text(d.note ?? 'Registration failed', style: T.bodySm.copyWith(color: C.error), overflow: TextOverflow.ellipsis),
                                if (d.status == 'test_registered') Text('Sandbox: not registered', style: T.bodySm.copyWith(color: C.secondary)),
                              ]),
                            ),
                          ]),
                        ),
                        TableCol(label: 'Years', numeric: true, sortValue: (d) => d.years, cell: (d) => Text('${d.years}')),
                        TableCol(label: 'Purchased', sortValue: (d) => d.purchasedAt, cell: (d) => Text(formatDate(d.purchasedAt))),
                        TableCol(label: 'Cost', numeric: true, sortValue: (d) => d.unitPrice, cell: (d) => Text(money(d.unitPrice, d.currency))),
                        TableCol(
                          label: 'Client',
                          sortValue: (d) => d.clientName.toLowerCase(),
                          cell: (d) => d.assigned
                              ? Text(d.clientName.isEmpty ? '—' : d.clientName, style: T.labelLg)
                              : const Pill('Unassigned', icon: Icons.schedule, bg: Color(0xFFFDEFC8), fg: Color(0xFF7A5200)),
                        ),
                        TableCol(label: 'Sold at', numeric: true, sortValue: (d) => d.sellPrice ?? -1, cell: (d) => Text(d.sellPrice == null ? '—' : money(d.sellPrice!, d.currency))),
                        TableCol(
                          label: 'Profit',
                          numeric: true,
                          sortValue: (d) => d.profit ?? -1e12,
                          cell: (d) => d.profit == null
                              ? Text('—', style: T.bodyMd.copyWith(color: C.outline))
                              : Pill(
                                  '${d.profit! >= 0 ? '+' : ''}${money(d.profit!, d.currency)}',
                                  bg: d.profit! >= 0 ? C.tertiaryFixed.withValues(alpha: 0.6) : C.errorContainer,
                                  fg: d.profit! >= 0 ? C.onTertiaryFixedVariant : C.error,
                                ),
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

/// Strong ease-out: starts fast so the UI feels responsive, settles gently.
const _easeOut = Cubic(0.23, 1, 0.32, 1);

/// Fades and lifts its child in once, staggered by [index]. Short (under 300ms) so it never feels slow.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 200 + index * 60),
        curve: _easeOut,
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child)),
        child: child,
      );
}

/// Summary tile. Pass [value] for a count (tap to filter when [onTap] is set) or [amount] for money.
class _StatCard extends StatefulWidget {
  const _StatCard({required this.label, required this.icon, required this.color, this.value, this.amount, this.currency = '', this.selected = false, this.onTap});
  final String label, currency;
  final IconData icon;
  final Color color;
  final int? value;
  final double? amount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hover = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final tappable = widget.onTap != null;
    final number = widget.value != null
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: widget.value!.toDouble()),
            duration: const Duration(milliseconds: 450),
            curve: _easeOut,
            builder: (_, v, _) => Text('${v.round()}', style: T.headlineLg),
          )
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: widget.amount ?? 0),
            duration: const Duration(milliseconds: 450),
            curve: _easeOut,
            builder: (_, v, _) => Text(money(v, widget.currency), style: T.headlineLg.copyWith(color: c), overflow: TextOverflow.ellipsis),
          );
    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: tappable ? (_) => setState(() => _pressed = true) : null,
        onTapUp: tappable ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: tappable ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            transform: Matrix4.translationValues(0, tappable && _hover && !_pressed ? -2 : 0, 0),
            decoration: BoxDecoration(
              color: C.surfaceLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.selected ? c.withValues(alpha: 0.7) : C.outlineVariant.withValues(alpha: 0.6), width: widget.selected ? 1.5 : 1),
              boxShadow: [BoxShadow(color: Color(_hover && tappable ? 0x1F000000 : 0x14000000), blurRadius: _hover && tappable ? 14 : 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(widget.icon, color: c, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  number,
                  Text(widget.label, style: T.labelSm.copyWith(color: C.secondary), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small rounded tile before each domain name; colour shows its state (failed / assigned / waiting).
class _DomainAvatar extends StatelessWidget {
  const _DomainAvatar({required this.failed, required this.assigned});
  final bool failed, assigned;

  @override
  Widget build(BuildContext context) {
    final color = failed ? C.error : (assigned ? C.tertiary : const Color(0xFFB87503));
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
      child: Icon(failed ? Icons.error_outline : Icons.language, color: color, size: 18),
    );
  }
}

/// Pick a client and set the selling price (defaults to what the reseller paid; anything on top is their profit).
class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.domain, required this.clients});
  final PurchasedDomain domain;
  final List<Client> clients;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _form = GlobalKey<FormState>();
  late String? _clientId = widget.domain.clientId;
  late final _price = TextEditingController(text: (widget.domain.sellPrice ?? widget.domain.unitPrice).toStringAsFixed(2));
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
      await resellerRepo.assignDomain(widget.domain.id, _clientId, double.parse(_price.text.trim()));
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
    final d = widget.domain;
    final sell = double.tryParse(_price.text.trim());
    return AlertDialog(
      title: Text('Assign ${d.domain}'),
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
