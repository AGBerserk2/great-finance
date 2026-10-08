import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/repositories/budgets_repository.dart';
import '../data/repositories/transactions_repository.dart';
import 'notifications.dart';

/// Registra, edita y borra movimientos de forma atómica y dispara las alertas de presupuesto.
class Ledger {
  Ledger(this.db, this.notifications)
      : transactions = TransactionsRepository(db),
        budgets = BudgetsRepository(db);

  final AppDatabase db;
  final AppNotifications notifications;
  final TransactionsRepository transactions;
  final BudgetsRepository budgets;

  Future<Txn> add(TransactionsCompanion entry) async {
    final (txn, alerts) = await db.transaction(() => addInTransaction(entry));
    await notifyAlerts(alerts);
    return txn;
  }

  /// Igual que [add] pero sin abrir transacción ni notificar; para componer con otras operaciones.
  Future<(Txn, List<BudgetAlert>)> addInTransaction(TransactionsCompanion entry) async {
    final txn = await transactions.add(entry);
    return (txn, await _alertsFor(txn));
  }

  Future<Txn> edit(Txn old, TransactionsCompanion changes) async {
    final (txn, alerts) = await db.transaction(() async {
      final updated = await transactions.replace(old, changes);
      return (updated, await _alertsFor(updated));
    });
    await notifyAlerts(alerts);
    return txn;
  }

  Future<void> delete(Txn txn) => db.transaction(() => transactions.delete(txn));

  Future<List<BudgetAlert>> _alertsFor(Txn txn) async {
    if (txn.kind != TxKind.expense || txn.categoryId == null) return const [];
    return budgets.checkAlerts(txn.categoryId!, txn.date);
  }

  Future<void> notifyAlerts(List<BudgetAlert> alerts) async {
    for (final alert in alerts) {
      try {
        await notifications.showBudgetAlert(alert);
      } catch (e, s) {
        debugPrint('No se pudo mostrar la alerta de presupuesto: $e\n$s');
      }
    }
  }
}
