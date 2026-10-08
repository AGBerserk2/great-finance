import 'package:drift/drift.dart';

import '../database.dart';

class CategoriesRepository {
  CategoriesRepository(this.db);
  final AppDatabase db;

  Stream<List<Category>> watch({CategoryKind? kind, bool includeArchived = false}) {
    final q = db.select(db.categories)
      ..where((c) {
        Expression<bool> e = const Constant(true);
        if (kind != null) e = e & c.kind.equalsValue(kind);
        if (!includeArchived) e = e & c.archived.equals(false);
        return e;
      })
      ..orderBy([(c) => OrderingTerm(expression: c.name)]);
    return q.watch();
  }

  Future<Category?> byName(String name) =>
      (db.select(db.categories)..where((c) => c.name.equals(name))).getSingleOrNull();

  Future<int> add({required String name, required String icon, required int color, required CategoryKind kind}) =>
      db.into(db.categories).insert(CategoriesCompanion.insert(name: name, icon: icon, color: color, kind: kind));

  Future<void> edit(int id, {required String name, required String icon, required int color}) =>
      (db.update(db.categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(name: Value(name), icon: Value(icon), color: Value(color)));

  Future<void> setArchived(int id, bool archived) =>
      (db.update(db.categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(archived: Value(archived)));
}
