import 'package:ag_finanzas/data/database.dart';
import 'package:ag_finanzas/data/repositories/budgets_repository.dart';
import 'package:ag_finanzas/data/repositories/payments_repository.dart';
import 'package:ag_finanzas/domain/dates.dart';
import 'package:ag_finanzas/domain/recurrence.dart';
import 'package:drift/drift.dart';

import 'test_db.dart';

/// Datos realistas y "pesados" (nombres largos, montos grandes) para revisar el diseño.
Future<void> seedRealisticData(AppDatabase db) async {
  final today = dateOnly(DateTime.now());
  final internet = await categoryId(db, 'Internet y teléfono');
  final food = await categoryId(db, 'Comida');
  final transport = await categoryId(db, 'Transporte');
  final salary = await categoryId(db, 'Sueldo');
  final budgets = BudgetsRepository(db);
  await budgets.setLimit(internet, today, 350000);
  await budgets.setLimit(food, today, 1500000);
  await budgets.setLimit(transport, today, 600000);

  Future<void> tx(TxKind kind, int cents, int? cat, {String? note, int? goal, int? debt}) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            kind: kind,
            amountCents: cents,
            categoryId: Value(cat),
            date: today,
            note: Value(note),
            goalId: Value(goal),
            debtId: Value(debt),
          ));

  final goal = await db.into(db.goals).insert(GoalsCompanion.insert(
      name: 'Fondo de emergencia para imprevistos del carro', targetCents: 123456789, deadline: Value(addMonths(today, 14))));
  await db.into(db.goals).insert(GoalsCompanion.insert(name: 'Viaje', targetCents: 5000000));
  final debt = await db.into(db.debts).insert(DebtsCompanion.insert(
      name: 'Préstamo personal del Banco Popular Dominicano',
      originalCents: 98765432,
      balanceCents: 87654321,
      annualRatePct: 18.75,
      monthlyPaymentCents: 1234567));
  await db.into(db.debts).insert(DebtsCompanion.insert(
      name: 'Tarjeta', originalCents: 5000000, balanceCents: 4800000, annualRatePct: 60, monthlyPaymentCents: 100000));

  await tx(TxKind.income, 123456789, salary, note: 'Sueldo quincena con bono');
  await tx(TxKind.expense, 1234567, food, note: 'Supermercado Nacional compra grande del mes con todo lo de la casa');
  await tx(TxKind.expense, 400000, internet);
  await tx(TxKind.expense, 520000, transport, note: 'Gasolina');
  await tx(TxKind.saving, 5000000, null, goal: goal);
  await tx(TxKind.expense, 1234567, await categoryId(db, 'Deudas'), debt: debt);

  await addPlanned(db, name: 'Internet Claro fibra óptica hogar', amount: 345678, category: internet, anchor: addDays(today, 2));
  await addPlanned(db,
      name: 'Transporte al trabajo',
      amount: 25000,
      category: transport,
      frequency: Frequency.daily,
      anchor: today,
      hour: 23,
      weekdays: weekdaysMonToFri);
  final overdue =
      await addPlanned(db, name: 'Cuota del préstamo del carro', amount: 1234567, debtId: debt, category: internet, anchor: addDays(today, -3));
  await db.into(db.paymentOccurrences).insert(PaymentOccurrencesCompanion.insert(plannedPaymentId: overdue, dueDate: addDays(today, -3)));
  await PaymentsRepository(db).ensureOccurrences(today);
}
