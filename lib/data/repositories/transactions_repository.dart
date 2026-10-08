import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../database.dart';

class TxnWithCategory {
  const TxnWithCategory(this.txn, this.category);
  final Txn txn;
  final Category? category;
}

class MonthTotals {
  const MonthTotals({required this.incomeCents, required this.expenseCents, required this.savingCents});
  final int incomeCents;
  final int expenseCents;
  final int savingCents;

  int get outflowCents => expenseCents + savingCents;
  int get availableCents => incomeCents - outflowCents;
}

/// Acceso a movimientos. `add`, `replace` y `delete` aplican/revierten los efectos sobre
/// deudas y ocurrencias; deben ejecutarse dentro de una transacción (ver `Ledger`).
class TransactionsRepository {
  TransactionsRepository(this.db);
  final AppDatabase db;

  Stream<List<TxnWithCategory>> watchMonth(DateTime month, {TxKind? kind, int? categoryId}) {
    final q = db.select(db.transactions).join([
      leftOuterJoin(db.categories, db.categories.id.equalsExp(db.transactions.categoryId)),
    ])
      ..where(db.transactions.date.isBiggerOrEqualValue(monthStart(month)) &
          db.transactions.date.isSmallerThanValue(nextMonthStart(month)))
      ..orderBy([
        OrderingTerm.desc(db.transactions.date),
        OrderingTerm.desc(db.transactions.id),
      ]);
    if (kind != null) q.where(db.transactions.kind.equalsValue(kind));
    if (categoryId != null) q.where(db.transactions.categoryId.equals(categoryId));
    return q.watch().map((rows) => [
          for (final r in rows) TxnWithCategory(r.readTable(db.transactions), r.readTableOrNull(db.categories)),
        ]);
  }

  Stream<MonthTotals> watchTotals(DateTime month) {
    final sum = db.transactions.amountCents.sum();
    final q = db.selectOnly(db.transactions)
      ..addColumns([db.transactions.kind, sum])
      ..where(db.transactions.date.isBiggerOrEqualValue(monthStart(month)) &
          db.transactions.date.isSmallerThanValue(nextMonthStart(month)))
      ..groupBy([db.transactions.kind]);
    return q.watch().map((rows) {
      final byKind = {for (final r in rows) r.read(db.transactions.kind)!: r.read(sum) ?? 0};
      return MonthTotals(
        incomeCents: byKind[TxKind.income.name] ?? 0,
        expenseCents: byKind[TxKind.expense.name] ?? 0,
        savingCents: byKind[TxKind.saving.name] ?? 0,
      );
    });
  }

  Future<Txn?> byId(int id) => (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Txn> add(TransactionsCompanion entry) async {
    final txn = await db.into(db.transactions).insertReturning(entry);
    await _applyEffects(txn, sign: 1);
    return txn;
  }

  /// Reemplaza un movimiento revirtiendo los efectos del anterior y aplicando los del nuevo.
  Future<Txn> replace(Txn old, TransactionsCompanion changes) async {
    await _applyEffects(old, sign: -1);
    await (db.update(db.transactions)..where((t) => t.id.equals(old.id))).write(changes);
    final updated = (await byId(old.id))!;
    await _applyEffects(updated, sign: 1);
    return updated;
  }

  /// Borra el movimiento y revierte sus efectos: devuelve el saldo a la deuda y, si venía de un
  /// pago planeado, regresa la ocurrencia a pendiente.
  Future<void> delete(Txn txn) async {
    await _applyEffects(txn, sign: -1);
    if (txn.occurrenceId != null) {
      await (db.update(db.paymentOccurrences)..where((o) => o.id.equals(txn.occurrenceId!))).write(
        const PaymentOccurrencesCompanion(status: Value(OccurrenceStatus.pending), snoozedUntil: Value(null)),
      );
    }
    await (db.delete(db.transactions)..where((t) => t.id.equals(txn.id))).go();
  }

  Future<void> _applyEffects(Txn txn, {required int sign}) async {
    if (txn.kind != TxKind.expense || txn.debtId == null) return;
    final debt = await (db.select(db.debts)..where((d) => d.id.equals(txn.debtId!))).getSingle();
    final balance = debt.balanceCents - sign * txn.amountCents;
    await (db.update(db.debts)..where((d) => d.id.equals(debt.id)))
        .write(DebtsCompanion(balanceCents: Value(balance < 0 ? 0 : balance)));
  }
}
