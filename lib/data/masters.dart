import 'repository.dart';

enum MasterFieldKind { text, integer, icon }

class MasterField {
  const MasterField(this.key, this.label, {this.kind = MasterFieldKind.text, this.required = false, this.hint = ''});
  final String key, label, hint;
  final MasterFieldKind kind;
  final bool required;
}

/// Describes one master table so a single screen and form can manage all of them.
class MasterDef {
  const MasterDef({required this.table, required this.title, required this.singular, required this.fields, required this.orderBy});
  final String table, title, singular, orderBy;
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
    fields: [MasterField('name', 'Name', required: true, hint: 'Compliance')],
  ),
  MasterDef(
    table: 'pricing_models',
    title: 'Pricing models',
    singular: 'pricing model',
    orderBy: 'name',
    fields: [
      MasterField('name', 'Name', required: true, hint: 'Per user'),
    ],
  ),
  MasterDef(
    table: 'currencies',
    title: 'Currencies',
    singular: 'currency',
    orderBy: 'code',
    fields: [
      MasterField('code', 'Code', required: true, hint: 'USD'),
      MasterField('name', 'Name', hint: 'US Dollar'),
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

  /// Plain values for dropdowns and chips, e.g. every tag name.
  Future<List<String>> values(String table, String column, {String? orderBy}) async {
    final rows = await sb.from(table).select(column).order(orderBy ?? column);
    return rows.map<String>((r) => r[column] as String).toList();
  }
}

final masterRepo = MasterRepository();
