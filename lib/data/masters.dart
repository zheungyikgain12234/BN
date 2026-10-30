import 'catalog_repository.dart';
import 'repository.dart';

enum MasterFieldKind { text, integer, decimal, icon, tld, money, percent, panel }

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
    readFrom: 'hosting_prices',
    title: 'Hosting Package prices',
    singular: 'hosting package price',
    orderBy: 'plan_name',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('plan_name', 'Plan', readOnly: true),
      MasterField('package_type_id', 'Plan from 20i', kind: MasterFieldKind.panel, required: true, hint: 'Select a plan and period'),
      MasterField('months', 'Months', kind: MasterFieldKind.integer, readOnly: true),
      MasterField('cost', 'Cost per period (20i)', kind: MasterFieldKind.money, readOnly: true),
      MasterField('profit_percent', 'Profit %', kind: MasterFieldKind.percent, required: true, hint: '10'),
      MasterField('price', 'Selling price per period', kind: MasterFieldKind.money, readOnly: true),
    ],
  ),
  MasterDef(
    table: 'vps_plan_prices',
    readFrom: 'vps_prices',
    title: 'VPS prices',
    singular: 'VPS price',
    orderBy: 'plan_name',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('plan_name', 'Plan', readOnly: true),
      MasterField('vps_type', 'Plan from 20i', kind: MasterFieldKind.panel, required: true, hint: 'Select a plan'),
      MasterField('cost_per_month', 'Cost per month (20i)', kind: MasterFieldKind.money, readOnly: true),
      MasterField('profit_percent', 'Profit %', kind: MasterFieldKind.percent, required: true, hint: '10'),
      MasterField('price_per_month', 'Selling price per month', kind: MasterFieldKind.money, readOnly: true),
    ],
  ),
  MasterDef(
    table: 'ssl_plan_prices',
    readFrom: 'ssl_prices',
    title: 'SSL prices',
    singular: 'SSL price',
    orderBy: 'plan_name',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('plan_name', 'Certificate', readOnly: true),
      MasterField('class_code', 'Certificate from 20i', kind: MasterFieldKind.panel, required: true, hint: 'Select a certificate and period'),
      MasterField('months', 'Months', kind: MasterFieldKind.integer, readOnly: true),
      MasterField('cost', 'Cost per period (20i)', kind: MasterFieldKind.money, readOnly: true),
      MasterField('profit_percent', 'Profit %', kind: MasterFieldKind.percent, required: true, hint: '10'),
      MasterField('price', 'Selling price per period', kind: MasterFieldKind.money, readOnly: true),
    ],
  ),
  MasterDef(
    table: 'vps_addon_prices',
    readFrom: 'vps_addons_priced',
    title: 'VPS add-on prices',
    singular: 'VPS add-on price',
    orderBy: 'label',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('label', 'Add-on', readOnly: true),
      MasterField('product_spec', 'Add-on from 20i', kind: MasterFieldKind.panel, required: true, hint: 'Select an add-on'),
      MasterField('cost_per_month', 'Cost per month (20i)', kind: MasterFieldKind.money, readOnly: true),
      MasterField('profit_percent', 'Profit %', kind: MasterFieldKind.percent, required: true, hint: '10'),
      MasterField('price_per_month', 'Selling price per month', kind: MasterFieldKind.money, readOnly: true),
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
  MasterDef(
    table: 'vps_locations',
    title: 'VPS locations',
    singular: 'VPS location',
    orderBy: 'label',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('label', 'Location', readOnly: true),
      MasterField('code', 'Location from 20i', kind: MasterFieldKind.panel, required: true, hint: 'Select a location'),
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

  /// Master tables whose cost column is copied from 20i (domain TLDs, VPS plans, VPS add-ons).
  static bool hasCost(MasterDef def) => const {'domain_tld_prices', 'hosting_plan_prices', 'ssl_plan_prices', 'vps_plan_prices', 'vps_addon_prices'}.contains(def.table);

  /// Re-reads 20i's current cost for every row already in Master Data, so selling prices follow 20i's price changes.
  /// Returns how many changed.
  Future<int> refreshCosts(MasterDef def, List<Map<String, dynamic>> rows) async {
    final domains = def.table == 'domain_tld_prices';
    final perMonth = def.table == 'vps_plan_prices' || def.table == 'vps_addon_prices';
    final costCol = domains ? 'cost_per_year' : (perMonth ? 'cost_per_month' : 'cost');
    final Map<String, double> fresh;
    String keyOf(Map<String, dynamic> r) => switch (def.table) {
          'domain_tld_prices' => '${r['tld']}',
          'vps_plan_prices' => '${r['vps_type']}',
          'hosting_plan_prices' => '${r['package_type_id']}|${r['months']}',
          'ssl_plan_prices' => '${r['class_code']}|${r['months']}',
          _ => '${r['product_spec']}',
        };
    if (domains) {
      fresh = {for (final t in await domainCartRepo.tldsFrom20i()) t.tld: t.cost};
    } else if (def.table == 'hosting_plan_prices') {
      fresh = {for (final p in await hostingCartRepo.panelHosting()) '${p.typeId}|${p.months}': p.price};
    } else if (def.table == 'ssl_plan_prices') {
      fresh = {for (final p in await sslCartRepo.panelCatalogue()) '${p.code}|${p.months}': p.price};
    } else if (def.table == 'vps_plan_prices') {
      fresh = {for (final p in vpsPlansPerMonth((await vpsCartRepo.panelCatalogue()).plans)) p.code.replaceFirst('vps:', 'vps-'): p.costPerMonth};
    } else {
      fresh = {for (final a in await vpsCartRepo.panelAddons()) a.spec: a.costPerMonth};
    }
    var changed = 0;
    for (final r in rows) {
      final cost = fresh[keyOf(r)];
      if (cost == null || cost == (r[costCol] as num?)?.toDouble()) continue;
      await sb.from(def.table).update({costCol: cost}).eq('id', r['id'] as String);
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
