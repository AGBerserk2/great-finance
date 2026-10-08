import 'package:drift/drift.dart';

import '../../domain/budget_status.dart';
import '../../domain/dates.dart';
import '../database.dart';

class BudgetLine {
  const BudgetLine({required this.category, required this.limitCents, required this.spentCents});
  final Category category;

  /// `null` si la categoría no tiene límite este mes.
  final int? limitCents;
  final int spentCents;

  BudgetLevel get level => budgetLevel(spentCents, limitCents ?? 0);
  double get ratio => (limitCents ?? 0) <= 0 ? 0 : spentCents / limitCents!;
}

class BudgetAlert {
  const BudgetAlert({
    required this.budgetId,
    required this.categoryName,
    required this.level,
    required this.spentCents,
    required this.limitCents,
  });
  final int budgetId;
  final String categoryName;
  final BudgetLevel level;
  final int spentCents;
  final int limitCents;
}

class BudgetsRepository {
  BudgetsRepository(this.db);
  final AppDatabase db;

  /// Todas las categorías de gasto activas con su límite (si tiene) y lo gastado en el mes.
  Stream<List<BudgetLine>> watchMonth(DateTime month) {
    return db
        .customSelect(
          'SELECT c.*, b.limit_cents AS limit_cents, '
          '(SELECT COALESCE(SUM(t.amount_cents), 0) FROM transactions t '
          ' WHERE t.category_id = c.id AND t.kind = ? AND t.date >= ? AND t.date < ?) AS spent '
          'FROM categories c '
          'LEFT JOIN budgets b ON b.category_id = c.id AND b.month = ? '
          'WHERE c.kind = ? AND c.archived = 0 '
          'ORDER BY c.name',
          variables: [
            Variable.withString(TxKind.expense.name),
            Variable.withDateTime(monthStart(month)),
            Variable.withDateTime(nextMonthStart(month)),
            Variable.withString(monthKey(month)),
            Variable.withString(CategoryKind.expense.name),
          ],
          readsFrom: {db.categories, db.budgets, db.transactions},
        )
        .watch()
        .map((rows) => [
              for (final r in rows)
                BudgetLine(
                  category: db.categories.map(r.data),
                  limitCents: r.readNullable<int>('limit_cents'),
                  spentCents: r.read<int>('spent'),
                ),
            ]);
  }

  /// Si el mes no tiene límites, copia los del mes más reciente que tenga.
  Future<void> ensureMonth(DateTime month) async {
    final key = monthKey(month);
    await db.transaction(() async {
      final existing = await (db.select(db.budgets)..where((b) => b.month.equals(key))).get();
      if (existing.isNotEmpty) return;
      final previous = await (db.select(db.budgets)
            ..where((b) => b.month.isSmallerThanValue(key))
            ..orderBy([(b) => OrderingTerm.desc(b.month)])
            ..limit(1))
          .getSingleOrNull();
      if (previous == null) return;
      final toCopy = await (db.select(db.budgets)..where((b) => b.month.equals(previous.month))).get();
      await db.batch((batch) {
        batch.insertAll(db.budgets, [
          for (final b in toCopy)
            BudgetsCompanion.insert(categoryId: b.categoryId, month: key, limitCents: b.limitCents),
        ]);
      });
    });
  }

  /// Fija el límite de una categoría en un mes (`null` o 0 lo quita). Reinicia las alertas.
  Future<void> setLimit(int categoryId, DateTime month, int? limitCents) async {
    final key = monthKey(month);
    if (limitCents == null || limitCents <= 0) {
      await (db.delete(db.budgets)..where((b) => b.categoryId.equals(categoryId) & b.month.equals(key))).go();
      return;
    }
    await db.into(db.budgets).insert(
          BudgetsCompanion.insert(categoryId: categoryId, month: key, limitCents: limitCents),
          onConflict: DoUpdate(
            (_) => BudgetsCompanion(
              limitCents: Value(limitCents),
              alerted80: const Value(false),
              alerted100: const Value(false),
            ),
            target: [db.budgets.categoryId, db.budgets.month],
          ),
        );
  }

  /// Revisa si la categoría cruzó el 80 % o el 100 % en el mes de [date] y aún no se avisó.
  /// Marca las banderas y devuelve las alertas a mostrar (como mucho una).
  Future<List<BudgetAlert>> checkAlerts(int categoryId, DateTime date) async {
    final budget = await (db.select(db.budgets)
          ..where((b) => b.categoryId.equals(categoryId) & b.month.equals(monthKey(date))))
        .getSingleOrNull();
    if (budget == null) return const [];

    final sum = db.transactions.amountCents.sum();
    final spent = await (db.selectOnly(db.transactions)
          ..addColumns([sum])
          ..where(db.transactions.categoryId.equals(categoryId) &
              db.transactions.kind.equalsValue(TxKind.expense) &
              db.transactions.date.isBiggerOrEqualValue(monthStart(date)) &
              db.transactions.date.isSmallerThanValue(nextMonthStart(date))))
        .map((r) => r.read(sum) ?? 0)
        .getSingle();

    final level = budgetLevel(spent, budget.limitCents);
    final crossed100 = level == BudgetLevel.over && !budget.alerted100;
    final crossed80 = level != BudgetLevel.ok && !budget.alerted80;
    if (!crossed100 && !crossed80) return const [];

    await (db.update(db.budgets)..where((b) => b.id.equals(budget.id))).write(BudgetsCompanion(
      alerted80: const Value(true),
      alerted100: Value(budget.alerted100 || crossed100),
    ));
    final category = await (db.select(db.categories)..where((c) => c.id.equals(categoryId))).getSingle();
    return [
      BudgetAlert(
        budgetId: budget.id,
        categoryName: category.name,
        level: crossed100 ? BudgetLevel.over : BudgetLevel.warning,
        spentCents: spent,
        limitCents: budget.limitCents,
      ),
    ];
  }
}
