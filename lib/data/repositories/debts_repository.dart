import 'package:drift/drift.dart';

import '../database.dart';

class DebtsRepository {
  DebtsRepository(this.db);
  final AppDatabase db;

  Stream<List<Debt>> watch() => (db.select(db.debts)
        ..where((d) => d.archived.equals(false))
        ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
      .watch();

  Future<Debt?> byId(int id) => (db.select(db.debts)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<int> add(DebtsCompanion entry) => db.into(db.debts).insert(entry);

  Future<void> edit(int id, DebtsCompanion changes) =>
      (db.update(db.debts)..where((d) => d.id.equals(id))).write(changes);

  /// Ajusta el saldo para que cuadre con el estado de cuenta, sin crear movimiento.
  Future<void> adjustBalance(int id, int balanceCents) =>
      edit(id, DebtsCompanion(balanceCents: Value(balanceCents < 0 ? 0 : balanceCents)));

  Future<void> archive(int id) => edit(id, const DebtsCompanion(archived: Value(true)));
}
