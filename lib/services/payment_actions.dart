import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/repositories/budgets_repository.dart';
import '../data/repositories/payments_repository.dart';
import '../domain/dates.dart';
import 'ledger.dart';

enum ActionResult { done, alreadyPaid, notFound }

/// Núcleo de las acciones sobre pagos planeados. Lo usan la UI y las notificaciones.
class PaymentActions {
  PaymentActions(this.db, this.ledger) : payments = PaymentsRepository(db);

  final AppDatabase db;
  final Ledger ledger;
  final PaymentsRepository payments;

  /// Registra el pago: crea el movimiento (gasto, o ahorro si está ligado a una meta), actualiza
  /// la deuda ligada y marca la ocurrencia como pagada. Si ya estaba pagada no hace nada.
  Future<ActionResult> markPaid(int occurrenceId, {int? amountCents, DateTime? date}) async {
    final (result, alerts) = await db.transaction(() async {
      final view = await payments.occurrenceById(occurrenceId);
      if (view == null) return (ActionResult.notFound, const <BudgetAlert>[]);
      if (view.occurrence.status == OccurrenceStatus.paid) return (ActionResult.alreadyPaid, const <BudgetAlert>[]);

      final p = view.payment;
      final isSaving = p.goalId != null;
      final (_, alerts) = await ledger.addInTransaction(TransactionsCompanion.insert(
        kind: isSaving ? TxKind.saving : TxKind.expense,
        amountCents: amountCents ?? p.amountCents,
        categoryId: Value(isSaving ? null : p.categoryId),
        date: dateOnly(date ?? DateTime.now()),
        note: Value(p.name),
        occurrenceId: Value(occurrenceId),
        debtId: Value(isSaving ? null : p.debtId),
        goalId: Value(p.goalId),
      ));
      await payments.setStatus(occurrenceId, OccurrenceStatus.paid);
      return (ActionResult.done, alerts);
    });
    await ledger.notifyAlerts(alerts);
    return result;
  }

  /// Pospone el recordatorio [days] días a partir de [today].
  Future<ActionResult> snooze(int occurrenceId, int days, {DateTime? today}) => _changeOpen(
        occurrenceId,
        OccurrenceStatus.snoozed,
        snoozedUntil: addDays(dateOnly(today ?? DateTime.now()), days),
      );

  /// "No lo pagaré": no vuelve a avisar por esta ocurrencia.
  Future<ActionResult> skip(int occurrenceId) => _changeOpen(occurrenceId, OccurrenceStatus.skipped);

  Future<ActionResult> _changeOpen(int occurrenceId, OccurrenceStatus status, {DateTime? snoozedUntil}) {
    return db.transaction(() async {
      final view = await payments.occurrenceById(occurrenceId);
      if (view == null) return ActionResult.notFound;
      if (view.occurrence.status == OccurrenceStatus.paid) return ActionResult.alreadyPaid;
      await payments.setStatus(occurrenceId, status, snoozedUntil: snoozedUntil);
      return ActionResult.done;
    });
  }
}
