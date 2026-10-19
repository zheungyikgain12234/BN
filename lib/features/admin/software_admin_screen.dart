import 'package:flutter/material.dart';

import '../../core/sortable_table.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/admin_repository.dart';
import '../../data/catalog_repository.dart';
import '../../data/masters.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../software/software_widgets.dart';

/// Admin: manage the software catalogue.
/// Company admins see and edit only their own company's apps; super admins see every company's.
class SoftwareAdminScreen extends StatefulWidget {
  const SoftwareAdminScreen({super.key});

  @override
  State<SoftwareAdminScreen> createState() => _SoftwareAdminScreenState();
}

class _SoftwareAdminScreenState extends State<SoftwareAdminScreen> {
  List<Product>? _products;
  Object? _error;

  bool get _superAdmin => AppState.instance.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await catalogRepo.managedProducts(onlyTenantId: _superAdmin ? null : AppState.instance.tenant?.id);
      if (mounted) setState(() => _products = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Product? p]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _SoftwareDialog(product: p));
    if (saved == true) _load();
  }

  Future<void> _delete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete software?'),
        content: Text('"${p.name}" and its screenshots and comments will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: C.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await catalogRepo.deleteProduct(p.id);
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
        Text('Manage software', style: T.headlineLg),
        const SizedBox(height: 16),
        Expanded(
          child: _error != null
              ? ErrorRetry(error: _error!, onRetry: _load)
              : _products == null
                  ? const Center(child: CircularProgressIndicator())
                  : SortableTable<Product>(
                      rows: _products!,
                      searchHint: 'Search software',
                      emptyLabel: 'No software yet. Add the first app.',
                      searchText: (p) => '${p.name} ${p.categoryName} ${p.tenantName} ${p.sku} ${p.tags.join(' ')}',
                      toolbar: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: const Text('Add software'))],
                      columns: [
                        TableCol(
                          label: 'Software',
                          sortValue: (p) => p.name.toLowerCase(),
                          cell: (p) => Row(mainAxisSize: MainAxisSize.min, children: [
                            AppIconTile(product: p, size: 36),
                            const SizedBox(width: 10),
                            Flexible(child: Text(p.name, style: T.labelLg, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                        TableCol(label: 'Category', sortValue: (p) => p.categoryName, cell: (p) => Text(p.categoryName.isEmpty ? '—' : p.categoryName)),
                        if (_superAdmin) TableCol(label: 'Company', sortValue: (p) => p.tenantName, cell: (p) => Text(p.tenantName.isEmpty ? 'All companies' : p.tenantName)),
                        TableCol(label: 'Version', sortValue: (p) => p.version, cell: (p) => Text(p.version.isEmpty ? '—' : p.version)),
                        TableCol(label: 'Price', numeric: true, sortValue: (p) => p.price ?? 0, cell: (p) => Text(p.price == null ? '—' : p.priceLabel)),
                      ],
                      actions: (p) => [
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(p)),
                        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: C.error), onPressed: () => _delete(p)),
                      ],
                    ),
        ),
      ]),
    );
  }
}

class _ShotDraft {
  _ShotDraft({this.id, required this.url, String title = ''}) : title = TextEditingController(text: title);
  final String? id; // null = not saved yet
  final String url;
  final TextEditingController title;
}

/// Add / edit form for one app, including icon and screenshot uploads.
class _SoftwareDialog extends StatefulWidget {
  const _SoftwareDialog({this.product});
  final Product? product;

  @override
  State<_SoftwareDialog> createState() => _SoftwareDialogState();
}

class _SoftwareDialogState extends State<_SoftwareDialog> {
  final _form = GlobalKey<FormState>();
  late final Product? _p = widget.product;
  late final _name = TextEditingController(text: _p?.name);
  late final _description = TextEditingController(text: _p?.description);
  late final _about = TextEditingController(text: _p?.about);
  late final _version = TextEditingController(text: _p?.version);
  late final _sku = TextEditingController(text: _p?.sku);
  late final _price = TextEditingController(text: _p?.price?.toString());

  List<SoftwareCategory> _categories = const [];
  List<Tenant> _companies = const [];
  List<String> _tagOptions = const [];
  List<String> _pricingModels = const [];
  List<String> _currencies = const [];
  String? _categoryId;
  String? _tenantId;
  String? _pricingModel;
  String? _currency;
  final Set<String> _tags = {};
  String? _iconUrl;
  final List<_ShotDraft> _shots = [];
  final List<String> _removedShotIds = [];
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  bool get _superAdmin => AppState.instance.isSuperAdmin;
  bool get _isNew => _p == null;

  @override
  void initState() {
    super.initState();
    _categoryId = _p?.categoryId;
    _iconUrl = _p?.imageUrl;
    _pricingModel = (_p?.pricingModel.isEmpty ?? true) ? null : _p!.pricingModel;
    _currency = (_p?.currency.isEmpty ?? true) ? null : _p!.currency;
    _tags.addAll(_p?.tags ?? const []);
    _tenantId = _isNew ? (_superAdmin ? null : AppState.instance.tenant?.id) : _p!.tenantId;
    _init();
  }

  Future<void> _init() async {
    try {
      final categories = await catalogRepo.categories();
      final tags = await masterRepo.values('software_tags', 'name');
      final models = await masterRepo.values('pricing_models', 'name');
      final currencies = await masterRepo.values('currencies', 'code');
      final companies = _superAdmin ? await adminRepo.companies() : const <Tenant>[];
      final shots = _isNew ? const <ProductScreenshot>[] : await catalogRepo.screenshots(_p!.id);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _companies = companies;
        // keep values an older app already has even if they are no longer in the master
        _tagOptions = {...tags, ..._tags}.toList();
        _pricingModels = {...models, ?_pricingModel}.toList();
        _currencies = {...currencies, ?_currency}.toList();
        if (!categories.any((c) => c.id == _categoryId)) _categoryId = null;
        _shots.addAll([for (final s in shots) _ShotDraft(id: s.id, url: s.url, title: s.title)]);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        showError(context, e);
        Navigator.pop(context, false);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _about, _version, _sku, _price]) {
      c.dispose();
    }
    for (final s in _shots) {
      s.title.dispose();
    }
    super.dispose();
  }

  String? _nullIfEmpty(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _pickIcon() async {
    setState(() => _uploading = true);
    try {
      final f = await catalogRepo.pickAndUploadImage('icons');
      if (f != null && mounted) setState(() => _iconUrl = f.url);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addShots() async {
    setState(() => _uploading = true);
    try {
      final files = await catalogRepo.pickAndUploadImages('screenshots');
      if (mounted) {
        setState(() => _shots.addAll([for (final f in files) _ShotDraft(url: f.url, title: f.name.replaceFirst(RegExp(r'\.[^.]+$'), ''))]));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final row = {
        'tenant_id': _tenantId,
        'category_id': _categoryId,
        'name': _name.text.trim(),
        'description': _nullIfEmpty(_description),
        'about': _nullIfEmpty(_about),
        'version': _nullIfEmpty(_version),
        'sku': _nullIfEmpty(_sku),
        'pricing_model': _pricingModel,
        'price': double.tryParse(_price.text.trim()),
        'currency': _currency,
        'tags': _tags.toList(),
        'image_url': _iconUrl,
      };
      final id = await catalogRepo.saveProduct(row, id: _p?.id);
      await catalogRepo.deleteScreenshots(_removedShotIds);
      final kept = _shots.where((s) => s.id != null).length;
      await catalogRepo.addScreenshots(
        id,
        [for (final s in _shots.where((s) => s.id == null)) ProductScreenshot(title: s.title.text.trim(), caption: '', url: s.url)],
        startAt: kept,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Widget _text(String label, TextEditingController c, String hint, {bool required = false, int lines = 1, TextInputType? type, double? width}) {
    final field = LabeledField(
      label: label,
      required: required,
      child: TextFormField(
        controller: c,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        keyboardType: type,
        decoration: fieldDecoration(hint: hint),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }

  Widget _dropdown(String label, String hint, String? value, List<DropdownMenuItem<String?>> items, ValueChanged<String?> onChanged, {double? width, bool required = false}) {
    final field = LabeledField(
      label: label,
      required: required,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: fieldDecoration(),
        hint: dropdownHint(hint),
        items: items,
        onChanged: onChanged,
        validator: required ? (v) => v == null ? '$label is required' : null : null,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final wide = screenW >= 720;
    final formW = wide ? 680.0 : screenW - 96; // AlertDialog measures intrinsic size, so no LayoutBuilder here
    final half = wide ? (formW - 12) / 2 : formW;
    return AlertDialog(
      title: Text(_isNew ? 'Add software' : 'Edit software'),
      scrollable: true,
      content: SizedBox(
        width: formW,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _iconPicker(),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 14, children: [
                    if (_superAdmin)
                      _dropdown(
                        'Company',
                        'Select a company',
                        _tenantId,
                        [
                          const DropdownMenuItem<String?>(value: null, child: Text('All companies (shared)')),
                          for (final t in _companies) DropdownMenuItem<String?>(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                        ],
                        (v) => setState(() => _tenantId = v),
                        width: half,
                      ),
                    _dropdown(
                      'Category',
                      'Select a category',
                      _categoryId,
                      [for (final c in _categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                      (v) => setState(() => _categoryId = v),
                      width: half,
                      required: true,
                    ),
                    _text('Name', _name, 'Microsoft 365 Business Premium', required: true, width: half),
                    _text('Version', _version, '2024.3', width: half),
                    _text('SKU', _sku, 'M365-BP-001', width: half),
                    _dropdown(
                      'Pricing model',
                      'Select a pricing model',
                      _pricingModel,
                      [for (final m in _pricingModels) DropdownMenuItem<String?>(value: m, child: Text(m))],
                      (v) => setState(() => _pricingModel = v),
                      width: half,
                    ),
                    _text('Price', _price, '22.00', type: const TextInputType.numberWithOptions(decimal: true), width: half),
                    _dropdown(
                      'Currency',
                      'Select a currency',
                      _currency,
                      [for (final c in _currencies) DropdownMenuItem<String?>(value: c, child: Text(c))],
                      (v) => setState(() => _currency = v),
                      width: half,
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _text('Short description', _description, 'One or two sentences shown on the app card', required: true, lines: 2),
                  const SizedBox(height: 14),
                  _text('About', _about, 'Full description shown in the pop-up', lines: 4),
                  const SizedBox(height: 14),
                  _tagPicker(),
                  const SizedBox(height: 16),
                  _screenshotEditor(),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: (_saving || _loading || _uploading) ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
      ],
    );
  }

  Widget _tagPicker() => LabeledField(
        label: 'Tags',
        helper: 'Choose from the Tags master.',
        child: _tagOptions.isEmpty
            ? Text('No tags in the master yet.', style: T.bodySm.copyWith(color: C.secondary))
            : Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in _tagOptions)
                  FilterChip(
                    label: Text(t),
                    selected: _tags.contains(t),
                    showCheckmark: false,
                    selectedColor: C.primaryFixed,
                    backgroundColor: C.surfaceLow,
                    labelStyle: T.labelMd,
                    onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
                  ),
              ]),
      );

  Widget _iconPicker() {
    final preview = Product(id: '', name: _name.text, imageUrl: _iconUrl, categoryIcon: _categories.where((c) => c.id == _categoryId).map((c) => c.icon).firstOrNull);
    return Row(children: [
      AppIconTile(product: preview, size: 64),
      const SizedBox(width: 14),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickIcon,
          icon: const Icon(Icons.upload_outlined, size: 16),
          label: Text(_iconUrl == null ? 'Upload icon' : 'Change icon'),
        ),
        if (_iconUrl != null) TextButton(onPressed: () => setState(() => _iconUrl = null), child: const Text('Remove')),
      ]),
    ]);
  }

  Widget _screenshotEditor() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Screenshots', style: T.labelMd)),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _addShots,
            icon: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_photo_alternate_outlined, size: 16),
            label: const Text('Add images'),
          ),
        ]),
        const SizedBox(height: 8),
        if (_shots.isEmpty) Text('No screenshots yet.', style: T.bodySm.copyWith(color: C.secondary)),
        for (final s in _shots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(s.url, width: 64, height: 42, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 42, child: Icon(Icons.broken_image_outlined)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: s.title, decoration: fieldDecoration(hint: 'Title'))),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline, size: 18, color: C.error),
                onPressed: () => setState(() {
                  if (s.id != null) _removedShotIds.add(s.id!);
                  _shots.remove(s);
                }),
              ),
            ]),
          ),
      ]);
}
