import 'package:ag_finanzas/data/database.dart';
import 'package:ag_finanzas/data/repositories/budgets_repository.dart';
import 'package:ag_finanzas/data/repositories/goals_repository.dart';
import 'package:ag_finanzas/data/repositories/payments_repository.dart';
import 'package:ag_finanzas/data/repositories/transactions_repository.dart';
import 'package:ag_finanzas/domain/budget_status.dart';
import 'package:ag_finanzas/domain/recurrence.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = newTestDb());
  tearDown(() => db.close());

  test('se cargan las categorías por defecto', () async {
    final all = await db.select(db.categories).get();
    expect(all.length, defaultCategories.length);
  });

  group('TransactionsRepository', () {
    test('totales del mes: el ahorro es salida pero no gasto', () async {
      final repo = TransactionsRepository(db);
      final food = await categoryId(db, 'Comida');
      final salary = await categoryId(db, 'Sueldo');
      final goal = await addGoal(db);
      await repo.add(TransactionsCompanion.insert(kind: TxKind.income, amountCents: 5000000, categoryId: Value(salary), date: DateTime(2026, 10, 1)));
      await repo.add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: 100000, categoryId: Value(food), date: DateTime(2026, 10, 2)));
      await repo.add(TransactionsCompanion.insert(kind: TxKind.saving, amountCents: 300000, goalId: Value(goal), date: DateTime(2026, 10, 3)));
      await repo.add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: 999, categoryId: Value(food), date: DateTime(2026, 11, 1)));

      final totals = await repo.watchTotals(DateTime(2026, 10)).first;
      expect(totals.incomeCents, 5000000);
      expect(totals.expenseCents, 100000);
      expect(totals.savingCents, 300000);
      expect(totals.availableCents, 5000000 - 400000);

      final lines = await BudgetsRepository(db).watchMonth(DateTime(2026, 10)).first;
      expect(lines.firstWhere((l) => l.category.id == food).spentCents, 100000);

      final goals = await GoalsRepository(db).watch().first;
      expect(goals.single.savedCents, 300000);
    });

    test('un gasto ligado a deuda baja el saldo y borrarlo lo devuelve', () async {
      final repo = TransactionsRepository(db);
      final debt = await addDebt(db, balance: 500000);
      final txn = await repo.add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: 200000, debtId: Value(debt), date: DateTime(2026, 10, 5)));
      expect((await (db.select(db.debts)..where((d) => d.id.equals(debt))).getSingle()).balanceCents, 300000);

      await repo.delete(txn);
      expect((await (db.select(db.debts)..where((d) => d.id.equals(debt))).getSingle()).balanceCents, 500000);
    });

    test('editar el monto de un pago de deuda ajusta la diferencia', () async {
      final repo = TransactionsRepository(db);
      final debt = await addDebt(db, balance: 500000);
      final txn = await repo.add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: 200000, debtId: Value(debt), date: DateTime(2026, 10, 5)));
      await repo.replace(txn, const TransactionsCompanion(amountCents: Value(150000)));
      expect((await (db.select(db.debts)..where((d) => d.id.equals(debt))).getSingle()).balanceCents, 350000);
    });

    test('borrar el movimiento de un pago planeado regresa la ocurrencia a pendiente', () async {
      final planned = await addPlanned(db, anchor: DateTime(2026, 10, 10));
      final occ = await db.into(db.paymentOccurrences).insert(PaymentOccurrencesCompanion.insert(
          plannedPaymentId: planned, dueDate: DateTime(2026, 10, 10), status: const Value(OccurrenceStatus.paid)));
      final repo = TransactionsRepository(db);
      final txn = await repo.add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: 250000, occurrenceId: Value(occ), date: DateTime(2026, 10, 10)));
      await repo.delete(txn);
      final o = await (db.select(db.paymentOccurrences)..where((x) => x.id.equals(occ))).getSingle();
      expect(o.status, OccurrenceStatus.pending);
    });
  });

  group('BudgetsRepository', () {
    test('ensureMonth copia los límites del último mes con presupuesto', () async {
      final repo = BudgetsRepository(db);
      final food = await categoryId(db, 'Comida');
      await repo.setLimit(food, DateTime(2026, 8), 800000);
      await repo.ensureMonth(DateTime(2026, 10));
      final lines = await repo.watchMonth(DateTime(2026, 10)).first;
      expect(lines.firstWhere((l) => l.category.id == food).limitCents, 800000);
      // No vuelve a copiar si ya hay límites.
      await repo.setLimit(food, DateTime(2026, 8), 1);
      await repo.ensureMonth(DateTime(2026, 10));
      expect((await repo.watchMonth(DateTime(2026, 10)).first).firstWhere((l) => l.category.id == food).limitCents, 800000);
    });

    test('alertas: una al 80 %, una al 100 %, nunca repetidas; editar el límite las reinicia', () async {
      final repo = BudgetsRepository(db);
      final txns = TransactionsRepository(db);
      final food = await categoryId(db, 'Comida');
      final oct = DateTime(2026, 10, 15);
      await repo.setLimit(food, oct, 10000);

      Future<List<BudgetAlert>> spend(int cents) async {
        await txns.add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: cents, categoryId: Value(food), date: oct));
        return repo.checkAlerts(food, oct);
      }

      expect(await spend(7000), isEmpty);
      expect((await spend(1500)).single.level, BudgetLevel.warning);
      expect(await spend(100), isEmpty);
      expect((await spend(2000)).single.level, BudgetLevel.over);
      expect(await spend(100), isEmpty);

      await repo.setLimit(food, oct, 100000);
      expect(await spend(100), isEmpty);
      await repo.setLimit(food, oct, 10000);
      expect((await spend(1)).single.level, BudgetLevel.over);
    });

    test('saltar directo al 100 % da una sola alerta de exceso', () async {
      final repo = BudgetsRepository(db);
      final food = await categoryId(db, 'Comida');
      final oct = DateTime(2026, 10, 15);
      await repo.setLimit(food, oct, 10000);
      await TransactionsRepository(db).add(TransactionsCompanion.insert(kind: TxKind.expense, amountCents: 20000, categoryId: Value(food), date: oct));
      final alerts = await repo.checkAlerts(food, oct);
      expect(alerts.single.level, BudgetLevel.over);
      expect(await repo.checkAlerts(food, oct), isEmpty);
    });
  });

  group('PaymentsRepository', () {
    test('ensureOccurrences no duplica y no crea vencimientos antes de hoy para pagos nuevos', () async {
      final repo = PaymentsRepository(db);
      await addPlanned(db, anchor: DateTime(2026, 9, 15));
      await repo.ensureOccurrences(DateTime(2026, 10, 8));
      await repo.ensureOccurrences(DateTime(2026, 10, 8));
      final occ = await db.select(db.paymentOccurrences).get();
      expect(occ.map((o) => o.dueDate), [DateTime(2026, 10, 15), DateTime(2026, 11, 15)]);
    });

    test('al volver después de días, crea los vencimientos pasados (quedan atrasados)', () async {
      final repo = PaymentsRepository(db);
      await addPlanned(db, anchor: DateTime(2026, 10, 15));
      await repo.ensureOccurrences(DateTime(2026, 10, 8)); // hasta 7 dic
      await repo.ensureOccurrences(DateTime(2027, 1, 20)); // sin abrir la app un tiempo
      final dates = (await db.select(db.paymentOccurrences).get()).map((o) => o.dueDate).toList();
      expect(dates, containsAll([DateTime(2026, 12, 15), DateTime(2027, 1, 15), DateTime(2027, 2, 15), DateTime(2027, 3, 15)]));
      final views = await repo.openOccurrences();
      expect(views.where((v) => v.isOverdue(DateTime(2027, 1, 20))).length, 4); // oct, nov, dic, ene
    });

    test('editar la regla regenera solo las pendientes futuras', () async {
      final repo = PaymentsRepository(db);
      final id = await addPlanned(db, anchor: DateTime(2026, 10, 10));
      await repo.ensureOccurrences(DateTime(2026, 10, 8));
      final first = (await db.select(db.paymentOccurrences).get()).first;
      await repo.setStatus(first.id, OccurrenceStatus.paid);

      await repo.updatePlanned(id, PlannedPaymentsCompanion(anchorDate: Value(DateTime(2026, 11, 20))), DateTime(2026, 10, 12));
      await repo.ensureOccurrences(DateTime(2026, 10, 12));
      final dates = (await db.select(db.paymentOccurrences).get()).map((o) => o.dueDate).toList();
      expect(dates, [DateTime(2026, 10, 10), DateTime(2026, 11, 20)]);
    });

    test('desactivar conserva historial y borra pendientes futuras', () async {
      final repo = PaymentsRepository(db);
      final id = await addPlanned(db, frequency: Frequency.weekly, anchor: DateTime(2026, 10, 1));
      await repo.ensureOccurrences(DateTime(2026, 10, 1));
      final first = (await db.select(db.paymentOccurrences).get()).first;
      await repo.setStatus(first.id, OccurrenceStatus.paid);
      await repo.deactivate(id, DateTime(2026, 10, 2));
      final left = await db.select(db.paymentOccurrences).get();
      expect(left.map((o) => o.id), [first.id]);
      expect(await repo.openOccurrences(), isEmpty);
    });
  });

  group('gasto diario', () {
    test('genera solo los días marcados y nunca queda atrasado si no se contesta', () async {
      final repo = PaymentsRepository(db);
      await addPlanned(db, name: 'Transporte', amount: 20000, frequency: Frequency.daily, anchor: DateTime(2026, 10, 8), weekdays: weekdaysMonToFri);
      await repo.ensureOccurrences(DateTime(2026, 10, 8));
      final dates = (await db.select(db.paymentOccurrences).get()).map((o) => o.dueDate).toList();
      expect(dates.first, DateTime(2026, 10, 8));
      expect(dates.any((d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday), isFalse);

      final views = await repo.openOccurrences();
      expect(views.where((v) => v.isOverdue(DateTime(2026, 10, 20))), isEmpty);
    });

    test('un diario pospuesto que se pasa sí cuenta como atrasado', () async {
      final repo = PaymentsRepository(db);
      await addPlanned(db, frequency: Frequency.daily, anchor: DateTime(2026, 10, 8));
      await repo.ensureOccurrences(DateTime(2026, 10, 8));
      final first = (await db.select(db.paymentOccurrences).get()).first;
      await repo.setStatus(first.id, OccurrenceStatus.snoozed, snoozedUntil: DateTime(2026, 10, 9));
      final view = (await repo.occurrenceById(first.id))!;
      expect(view.isOverdue(DateTime(2026, 10, 10)), isTrue);
    });
  });
}
