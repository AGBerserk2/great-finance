import 'package:ag_finanzas/data/database.dart';
import 'package:ag_finanzas/data/repositories/budgets_repository.dart';
import 'package:ag_finanzas/data/repositories/payments_repository.dart';
import 'package:ag_finanzas/domain/budget_status.dart';
import 'package:ag_finanzas/domain/recurrence.dart';
import 'package:ag_finanzas/services/backup_service.dart';
import 'package:ag_finanzas/services/ledger.dart';
import 'package:ag_finanzas/services/payment_actions.dart';
import 'package:ag_finanzas/services/payment_scheduler.dart';
import 'package:ag_finanzas/services/reminder_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late FakeNotifications notifications;
  late Ledger ledger;
  late PaymentActions actions;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() {
    db = newTestDb();
    notifications = FakeNotifications();
    ledger = Ledger(db, notifications);
    actions = PaymentActions(db, ledger);
  });
  tearDown(() => db.close());

  Future<int> occurrenceFor(int planned, DateTime due) => db
      .into(db.paymentOccurrences)
      .insert(PaymentOccurrencesCompanion.insert(plannedPaymentId: planned, dueDate: due));

  group('PaymentActions.markPaid', () {
    test('crea el gasto, marca pagado y dispara alerta de presupuesto', () async {
      final luz = await categoryId(db, 'Luz');
      await BudgetsRepository(db).setLimit(luz, DateTime(2026, 10), 250000);
      final planned = await addPlanned(db, category: luz, anchor: DateTime(2026, 10, 10));
      final occ = await occurrenceFor(planned, DateTime(2026, 10, 10));

      expect(await actions.markPaid(occ, date: DateTime(2026, 10, 10, 14)), ActionResult.done);

      final txns = await db.select(db.transactions).get();
      expect(txns.single.kind, TxKind.expense);
      expect(txns.single.amountCents, 250000);
      expect(txns.single.categoryId, luz);
      expect(txns.single.occurrenceId, occ);
      expect(txns.single.date, DateTime(2026, 10, 10));
      final o = await (db.select(db.paymentOccurrences)..where((x) => x.id.equals(occ))).getSingle();
      expect(o.status, OccurrenceStatus.paid);
      expect(notifications.alerts.single.level, BudgetLevel.over);
    });

    test('doble markPaid no duplica', () async {
      final planned = await addPlanned(db, anchor: DateTime(2026, 10, 10));
      final occ = await occurrenceFor(planned, DateTime(2026, 10, 10));
      await actions.markPaid(occ);
      expect(await actions.markPaid(occ), ActionResult.alreadyPaid);
      expect((await db.select(db.transactions).get()).length, 1);
    });

    test('ligado a deuda baja el saldo', () async {
      final debt = await addDebt(db, balance: 1000000);
      final planned = await addPlanned(db, amount: 300000, debtId: debt, category: await categoryId(db, 'Deudas'), anchor: DateTime(2026, 10, 10));
      final occ = await occurrenceFor(planned, DateTime(2026, 10, 10));
      await actions.markPaid(occ);
      final d = await (db.select(db.debts)..where((x) => x.id.equals(debt))).getSingle();
      expect(d.balanceCents, 700000);
    });

    test('ligado a meta crea un ahorro sin categoría', () async {
      final goal = await addGoal(db);
      final planned = await addPlanned(db, amount: 500000, goalId: goal, anchor: DateTime(2026, 10, 10));
      final occ = await occurrenceFor(planned, DateTime(2026, 10, 10));
      await actions.markPaid(occ);
      final t = (await db.select(db.transactions).get()).single;
      expect(t.kind, TxKind.saving);
      expect(t.goalId, goal);
      expect(t.categoryId, isNull);
    });

    test('monto distinto al planeado', () async {
      final planned = await addPlanned(db, anchor: DateTime(2026, 10, 10));
      final occ = await occurrenceFor(planned, DateTime(2026, 10, 10));
      await actions.markPaid(occ, amountCents: 199900);
      expect((await db.select(db.transactions).get()).single.amountCents, 199900);
    });

    test('ocurrencia inexistente', () async {
      expect(await actions.markPaid(999), ActionResult.notFound);
    });
  });

  group('snooze y skip', () {
    test('snooze pospone N días; skip omite; ninguno toca pagos ya pagados', () async {
      final planned = await addPlanned(db, anchor: DateTime(2026, 10, 10));
      final a = await occurrenceFor(planned, DateTime(2026, 10, 10));
      final b = await occurrenceFor(planned, DateTime(2026, 11, 10));

      expect(await actions.snooze(a, 3, today: DateTime(2026, 10, 10, 9)), ActionResult.done);
      var o = await (db.select(db.paymentOccurrences)..where((x) => x.id.equals(a))).getSingle();
      expect(o.status, OccurrenceStatus.snoozed);
      expect(o.snoozedUntil, DateTime(2026, 10, 13));

      expect(await actions.skip(b), ActionResult.done);
      o = await (db.select(db.paymentOccurrences)..where((x) => x.id.equals(b))).getSingle();
      expect(o.status, OccurrenceStatus.skipped);

      await actions.markPaid(a);
      expect(await actions.snooze(a, 1), ActionResult.alreadyPaid);
      expect(await actions.skip(a), ActionResult.alreadyPaid);
      o = await (db.select(db.paymentOccurrences)..where((x) => x.id.equals(a))).getSingle();
      expect(o.status, OccurrenceStatus.paid);
    });
  });

  group('PaymentScheduler', () {
    test('programa recordatorios futuros con días de aviso y hora', () async {
      await addPlanned(db, name: 'Luz', amount: 250000, anchor: DateTime(2026, 10, 10), hour: 9, daysBefore: 2);
      final scheduler = PaymentScheduler(db, notifications, clock: () => DateTime(2026, 10, 8, 8));
      await scheduler.sync();

      expect(notifications.scheduled.length, 2); // 10 oct y 10 nov
      final first = notifications.scheduled.first;
      expect(first.when, DateTime(2026, 10, 8, 9));
      expect(first.title, 'Luz · RD\$2,500.00');
      expect(first.body, 'Vence el sáb 10 oct');
    });

    test('si el aviso anticipado ya pasó, avisa el mismo día del vencimiento', () async {
      await addPlanned(db, anchor: DateTime(2026, 10, 10), hour: 9, daysBefore: 2);
      await PaymentScheduler(db, notifications, clock: () => DateTime(2026, 10, 8, 10)).sync();
      expect(notifications.scheduled.first.when, DateTime(2026, 10, 10, 9));
      expect(notifications.scheduled.first.body, 'Vence hoy');
    });

    test('sync repetido no duplica y no programa pagados ni omitidos', () async {
      final planned = await addPlanned(db, frequency: Frequency.weekly, anchor: DateTime(2026, 10, 9));
      final scheduler = PaymentScheduler(db, notifications, clock: () => DateTime(2026, 10, 8, 8));
      await scheduler.sync();
      final count = notifications.scheduled.length;
      await scheduler.sync();
      expect(notifications.scheduled.length, count);
      expect((await db.select(db.paymentOccurrences).get()).length, count);

      final occ = await (db.select(db.paymentOccurrences)..where((o) => o.plannedPaymentId.equals(planned))).get();
      await actions.markPaid(occ[0].id);
      await actions.skip(occ[1].id);
      await actions.snooze(occ[2].id, 1, today: DateTime(2026, 10, 8));
      await scheduler.sync();
      expect(notifications.scheduled.length, count - 2);
      expect(notifications.scheduled.first.when, DateTime(2026, 10, 9, 9)); // pospuesto a mañana
    });
  });

  test('reminderBody: mañana y vencido', () {
    final view = OccurrenceView(
      PaymentOccurrence(id: 1, plannedPaymentId: 1, dueDate: DateTime(2026, 10, 10), status: OccurrenceStatus.snoozed),
      PlannedPayment(
        id: 1, name: 'Agua', amountCents: 50000, frequency: Frequency.monthly, anchorDate: DateTime(2026, 10, 10),
        remindHour: 9, remindMinute: 0, remindDaysBefore: 0, weekdays: 127, active: true,
      ),
    );
    expect(reminderBody(view, DateTime(2026, 10, 9, 9)), 'Vence mañana');
    expect(reminderBody(view, DateTime(2026, 10, 12, 9)), 'Venció el sáb 10 oct');
  });

  group('BackupService', () {
    test('exportar → importar en otra base da el mismo contenido', () async {
      final debt = await addDebt(db);
      final planned = await addPlanned(db, debtId: debt, anchor: DateTime(2026, 10, 10));
      final occ = await occurrenceFor(planned, DateTime(2026, 10, 10));
      await actions.markPaid(occ);
      await BudgetsRepository(db).setLimit(await categoryId(db, 'Comida'), DateTime(2026, 10), 900000);
      await db.setSetting('remind_hour', '8');

      final service = BackupService(db);
      final json = await service.exportJson(now: DateTime(2026, 10, 8));

      final other = newTestDb();
      final otherService = BackupService(other);
      await otherService.importData(otherService.parse(json));
      final reexported = await otherService.exportJson(now: DateTime(2026, 10, 8));
      expect(reexported, json);
      await other.close();
    });

    test('rechaza archivos inválidos o de versiones más nuevas sin tocar los datos', () async {
      final service = BackupService(db);
      expect(() => service.parse('no json'), throwsA(isA<BackupFormatException>()));
      expect(() => service.parse('{"app":"otra","tables":{}}'), throwsA(isA<BackupFormatException>()));
      expect(() => service.parse('{"app":"ag_finanzas","schemaVersion":99,"tables":{}}'),
          throwsA(isA<BackupFormatException>()));
      expect((await db.select(db.categories).get()).length, defaultCategories.length);
    });

    test('un import que falla a mitad no borra nada', () async {
      final service = BackupService(db);
      final bad = {
        'app': 'ag_finanzas',
        'schemaVersion': 1,
        'tables': {
          'categories': [
            {'id': 1, 'name': 'X', 'icon': 'x', 'color': 0, 'kind': 'expense', 'archived': false},
          ],
          'transactions': [
            {'id': 1, 'kind': 'expense', 'amountCents': 5, 'categoryId': 999, 'date': 0, 'createdAt': 0},
          ],
        },
      };
      await expectLater(service.importData(bad), throwsA(isA<BackupFormatException>()));
      expect((await db.select(db.categories).get()).length, defaultCategories.length);
    });
  });
}
