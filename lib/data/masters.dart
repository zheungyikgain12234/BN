import 'catalog_repository.dart';
import 'repository.dart';

enum MasterFieldKind { text, integer, decimal, icon, tld, money, percent }

class MasterField {
  const MasterField(this.key, this.label, {this.kind = MasterFieldKind.text, this.required = false, this.hint = '', this.readOnly = false});
  final String key, label, hint;
  final MasterFieldKind kind;
  final bool required;

  /// Shown in the table but not typed in the form (it is filled in from 20i).
  final bool readOnly;
}

/// Describes one master table so a single screen and form can manage all of them.
class MasterDef {
  const MasterDef({required this.table, required this.title, required this.singular, required this.fields, required this.orderBy, required this.usageKind, required this.valueKey, this.readFrom});
  final String table, title, singular, orderBy;

  /// How apps reference this master (see public.reassign_master) and which column holds that reference.
  final String usageKind, valueKey;

  /// A view to read the rows from when it adds computed columns (writes still go to [table]).
  final String? readFrom;
  final List<MasterField> fields;

  /// Column shown as the row's name (the first field).
  String get nameKey => fields.first.key;
}

const masterDefs = <MasterDef>[
  MasterDef(
    table: 'software_categories',
    title: 'Categories',
    singular: 'category',
    orderBy: 'name',
    usageKind: 'category',
    valueKey: 'id',
    fields: [
      MasterField('name', 'Name', required: true, hint: 'Productivity'),
      MasterField('icon', 'Icon', kind: MasterFieldKind.icon, hint: 'Select an icon'),
    ],
  ),
  MasterDef(
    table: 'software_tags',
    title: 'Tags',
    singular: 'tag',
    orderBy: 'name',
    usageKind: 'tag',
    valueKey: 'name',
    fields: [MasterField('name', 'Name', required: true, hint: 'Compliance')],
  ),
  MasterDef(
    table: 'pricing_models',
    title: 'Pricing models',
    singular: 'pricing model',
    orderBy: 'name',
    usageKind: 'pricing_model',
    valueKey: 'name',
    fields: [
      MasterField('name', 'Name', required: true, hint: 'Per user'),
    ],
  ),
  MasterDef(
    table: 'domain_tld_prices',
    readFrom: 'domain_prices',
    title: 'Domain prices',
    singular: 'domain price',
    orderBy: 'tld',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('tld', 'TLD', kind: MasterFieldKind.tld, required: true, hint: 'Select an extension'),
      MasterField('cost_per_year', 'Cost per year (20i)', kind: MasterFieldKind.money, readOnly: true),
      MasterField('profit_percent', 'Profit %', kind: MasterFieldKind.percent, required: true, hint: '10'),
      MasterField('price_per_year', 'Selling price per year', kind: MasterFieldKind.money, readOnly: true),
    ],
  ),
  MasterDef(
    table: 'hosting_plan_prices',
    title: 'Hosting Package prices',
    singular: 'hosting package price',
    orderBy: 'plan_name',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('plan_name', 'Plan name', required: true, hint: 'Starter hosting'),
      MasterField('package_type_id', '20i plan id / shop code', required: true, hint: 'Pick from 20i, or paste a shop code'),
      MasterField('months', 'Months', kind: MasterFieldKind.integer, required: true, hint: '12'),
      MasterField('price', 'Price (whole period)', kind: MasterFieldKind.decimal, required: true, hint: '60.00'),
    ],
  ),
  MasterDef(
    table: 'vps_plan_prices',
    title: 'VPS prices',
    singular: 'VPS price',
    orderBy: 'plan_name',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('plan_name', 'Plan name', required: true, hint: '1 Core Unmanaged VPS'),
      MasterField('vps_type', '20i VPS type', required: true, hint: 'Pick from 20i, or vps-a'),
      MasterField('months', 'Months', kind: MasterFieldKind.integer, required: true, hint: '1'),
      MasterField('price', 'Price (whole period)', kind: MasterFieldKind.decimal, required: true, hint: '25.00'),
    ],
  ),
  MasterDef(
    table: 'ssl_plan_prices',
    title: 'SSL prices',
    singular: 'SSL price',
    orderBy: 'plan_name',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('plan_name', 'Certificate name', required: true, hint: 'Simple SSL'),
      MasterField('class_code', '20i class code', required: true, hint: 'tucows-rapidssl, tucows-rapidssl_wildcard or tucows-truebizid_ev'),
      MasterField('months', 'Months', kind: MasterFieldKind.integer, required: true, hint: '12'),
      MasterField('price', 'Price (whole period)', kind: MasterFieldKind.decimal, required: true, hint: '63.96'),
    ],
  ),
  MasterDef(
    table: 'vps_addon_prices',
    title: 'VPS add-on prices',
    singular: 'VPS add-on price',
    orderBy: 'label',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('label', 'Add-on name', required: true, hint: 'cPanel Pro (Max 30 Sites)'),
      MasterField('product_spec', '20i add-on code', required: true, hint: 'Pick from 20i, or vps_addon-cpanelpro, vps_addon-backup, vps_addon-disk100GB'),
      MasterField('months', 'Months', kind: MasterFieldKind.integer, required: true, hint: '1'),
      MasterField('price', 'Price (whole period)', kind: MasterFieldKind.decimal, required: true, hint: '51.17'),
    ],
  ),
  MasterDef(
    table: 'vps_os_options',
    title: 'VPS operating systems',
    singular: 'operating system',
    orderBy: 'label',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('label', 'Name', required: true, hint: 'Ubuntu 22.04'),
      MasterField('code', '20i OS code', required: true, hint: 'Pick from 20i, or ubuntu22.04'),
    ],
  ),
];

class MasterRepository {
  Future<List<Map<String, dynamic>>> list(MasterDef def) async {
    final rows = await sb.from(def.readFrom ?? def.table).select().order(def.orderBy).order(def.nameKey);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> save(MasterDef def, Map<String, dynamic> values, {String? id}) async {
    if (id == null) {
      await sb.from(def.table).insert(values);
    } else {
      await sb.from(def.table).update(values).eq('id', id);
    }
  }

  Future<void> delete(MasterDef def, String id) => sb.from(def.table).delete().eq('id', id);

  /// How many apps still use this master value.
  Future<int> usageCount(MasterDef def, Map<String, dynamic> row) async => def.usageKind.isEmpty
      ? 0 // nothing references this master (e.g. domain prices)
      : (await sb.rpc('master_usage', params: {'kind': def.usageKind, 'old_value': '${row[def.valueKey]}'})) as int;

  /// Moves every app from this value to [replacement] (null clears it), then deletes the master row.
  Future<void> reassignAndDelete(MasterDef def, Map<String, dynamic> row, String? replacement) async {
    await sb.rpc('reassign_master', params: {'kind': def.usageKind, 'old_value': '${row[def.valueKey]}', 'new_value': replacement});
    await delete(def, row['id'] as String);
  }

  /// Domains: re-reads 20i's current yearly cost for every TLD already in Master Data. Returns how many changed.
  Future<int> refreshDomainCosts(List<Map<String, dynamic>> rows) async {
    final fresh = {for (final t in await domainCartRepo.tldsFrom20i()) t.tld: t.cost};
    var changed = 0;
    for (final r in rows) {
      final cost = fresh['${r['tld']}'];
      if (cost == null || cost == (r['cost_per_year'] as num?)?.toDouble()) continue;
      await sb.from('domain_tld_prices').update({'cost_per_year': cost}).eq('id', r['id'] as String);
      changed++;
    }
    return changed;
  }

  /// Plain values for dropdowns and chips, e.g. every tag name.
  Future<List<String>> values(String table, String column, {String? orderBy}) async {
    final rows = await sb.from(table).select(column).order(orderBy ?? column);
    return rows.map<String>((r) => r[column] as String).toList();
  }
}

final masterRepo = MasterRepository();
