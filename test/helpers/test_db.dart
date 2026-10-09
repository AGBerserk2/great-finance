import 'package:ag_finanzas/data/database.dart';
import 'package:ag_finanzas/data/repositories/budgets_repository.dart';
import 'package:ag_finanzas/domain/recurrence.dart';
import 'package:ag_finanzas/services/notifications.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';

AppDatabase newTestDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

class FakeNotifications implements AppNotifications {
  final alerts = <BudgetAlert>[];
  final scheduled = <ReminderRequest>[];
  int cancelCalls = 0;

  @override
  Future<void> showBudgetAlert(BudgetAlert alert) async => alerts.add(alert);

  @override
  Future<void> cancelScheduledReminders() async {
    cancelCalls++;
    scheduled.clear();
  }

  @override
  Future<void> scheduleReminder(ReminderRequest request) async => scheduled.add(request);
}

Future<int> categoryId(AppDatabase db, String name) async =>
    (await (db.select(db.categories)..where((c) => c.name.equals(name))).getSingle()).id;

Future<int> addDebt(AppDatabase db, {int balance = 1000000}) => db.into(db.debts).insert(DebtsCompanion.insert(
      name: 'Préstamo',
      originalCents: balance,
      balanceCents: balance,
      annualRatePct: 18,
      monthlyPaymentCents: 100000,
    ));

Future<int> addGoal(AppDatabase db) =>
    db.into(db.goals).insert(GoalsCompanion.insert(name: 'Viaje', targetCents: 5000000));

Future<int> addPlanned(
  AppDatabase db, {
  String name = 'Luz',
  int amount = 250000,
  int? category,
  Frequency frequency = Frequency.monthly,
  required DateTime anchor,
  int hour = 9,
  int daysBefore = 0,
  int weekdays = 127,
  int? debtId,
  int? goalId,
}) =>
    db.into(db.plannedPayments).insert(PlannedPaymentsCompanion.insert(
          name: name,
          amountCents: amount,
          categoryId: Value(category),
          frequency: frequency,
          anchorDate: anchor,
          remindHour: hour,
          remindMinute: 0,
          remindDaysBefore: Value(daysBefore),
          weekdays: Value(weekdays),
          debtId: Value(debtId),
          goalId: Value(goalId),
        ));
