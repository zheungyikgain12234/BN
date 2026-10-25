import 'repository.dart';

enum MasterFieldKind { text, integer, decimal, icon }

class MasterField {
  const MasterField(this.key, this.label, {this.kind = MasterFieldKind.text, this.required = false, this.hint = ''});
  final String key, label, hint;
  final MasterFieldKind kind;
  final bool required;
}

/// Describes one master table so a single screen and form can manage all of them.
class MasterDef {
  const MasterDef({required this.table, required this.title, required this.singular, required this.fields, required this.orderBy, required this.usageKind, required this.valueKey});
  final String table, title, singular, orderBy;

  /// How apps reference this master (see public.reassign_master) and which column holds that reference.
  final String usageKind, valueKey;
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
    table: 'currencies',
    title: 'Currencies',
    singular: 'currency',
    orderBy: 'code',
    usageKind: 'currency',
    valueKey: 'code',
    fields: [
      MasterField('code', 'Code', required: true, hint: 'USD'),
      MasterField('name', 'Name', hint: 'US Dollar'),
    ],
  ),
  MasterDef(
    table: 'domain_tld_prices',
    title: 'Domain prices',
    singular: 'domain price',
    orderBy: 'tld',
    usageKind: '',
    valueKey: 'id',
    fields: [
      MasterField('tld', 'Extension', required: true, hint: 'com or co.uk (no dot)'),
      MasterField('years', 'Years', kind: MasterFieldKind.integer, required: true, hint: '1'),
      MasterField('price', 'Price (whole duration)', kind: MasterFieldKind.decimal, required: true, hint: '21.74'),
      MasterField('currency', 'Currency', required: true, hint: 'USD'),
    ],
  ),
];

class MasterRepository {
  Future<List<Map<String, dynamic>>> list(MasterDef def) async {
    final rows = await sb.from(def.table).select().order(def.orderBy).order(def.nameKey);
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

  /// Plain values for dropdowns and chips, e.g. every tag name.
  Future<List<String>> values(String table, String column, {String? orderBy}) async {
    final rows = await sb.from(table).select(column).order(orderBy ?? column);
    return rows.map<String>((r) => r[column] as String).toList();
  }
}

final masterRepo = MasterRepository();
