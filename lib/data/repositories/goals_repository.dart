import 'package:drift/drift.dart';

import '../database.dart';

class GoalProgress {
  const GoalProgress(this.goal, this.savedCents);
  final Goal goal;
  final int savedCents;

  double get ratio => goal.targetCents <= 0 ? 0 : (savedCents / goal.targetCents).clamp(0, 1).toDouble();
  bool get done => savedCents >= goal.targetCents;
}

class GoalsRepository {
  GoalsRepository(this.db);
  final AppDatabase db;

  Stream<List<GoalProgress>> watch() {
    final saved = db.transactions.amountCents.sum();
    final q = db.select(db.goals).join([
      leftOuterJoin(
        db.transactions,
        db.transactions.goalId.equalsExp(db.goals.id) & db.transactions.kind.equalsValue(TxKind.saving),
        useColumns: false,
      ),
    ])
      ..addColumns([saved])
      ..where(db.goals.archived.equals(false))
      ..groupBy([db.goals.id])
      ..orderBy([OrderingTerm.asc(db.goals.createdAt)]);
    return q.watch().map((rows) => [for (final r in rows) GoalProgress(r.readTable(db.goals), r.read(saved) ?? 0)]);
  }

  Stream<List<Goal>> watchActive() =>
      (db.select(db.goals)..where((g) => g.archived.equals(false))).watch();

  Future<int> add(GoalsCompanion entry) => db.into(db.goals).insert(entry);

  Future<void> edit(int id, GoalsCompanion changes) =>
      (db.update(db.goals)..where((g) => g.id.equals(id))).write(changes);

  Future<void> archive(int id) =>
      (db.update(db.goals)..where((g) => g.id.equals(id))).write(const GoalsCompanion(archived: Value(true)));
}
