import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/recurrence.dart';
import '../database.dart';

const occurrenceHorizonDays = 60;

class OccurrenceView {
  const OccurrenceView(this.occurrence, this.payment);
  final PaymentOccurrence occurrence;
  final PlannedPayment payment;

  bool get isDaily => payment.frequency == Frequency.daily;

  /// Pendiente (o pospuesto) con fecha ya vencida respecto a [today]. Los gastos diarios no
  /// contestados no se acumulan como atrasados: si no se marcó "Pagué", ese día no se gastó.
  bool isOverdue(DateTime today) {
    final t = dateOnly(today);
    if (isDaily && occurrence.status == OccurrenceStatus.pending) return false;
    return switch (occurrence.status) {
      OccurrenceStatus.pending => occurrence.dueDate.isBefore(t),
      OccurrenceStatus.snoozed => occurrence.snoozedUntil!.isBefore(t),
      _ => false,
    };
  }

  bool get isOpen => occurrence.status == OccurrenceStatus.pending || occurrence.status == OccurrenceStatus.snoozed;
}

class PaymentsRepository {
  PaymentsRepository(this.db);
  final AppDatabase db;

  Stream<List<PlannedPayment>> watchPlanned() => (db.select(db.plannedPayments)
        ..where((p) => p.active.equals(true))
        ..orderBy([(p) => OrderingTerm(expression: p.name)]))
      .watch();

  Future<PlannedPayment?> plannedById(int id) =>
      (db.select(db.plannedPayments)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<int> addPlanned(PlannedPaymentsCompanion entry) => db.into(db.plannedPayments).insert(entry);

  /// Actualiza la regla y descarta las ocurrencias pendientes de hoy en adelante para que se
  /// regeneren con la regla nueva.
  Future<void> updatePlanned(int id, PlannedPaymentsCompanion changes, DateTime today) async {
    await db.transaction(() async {
      await (db.update(db.plannedPayments)..where((p) => p.id.equals(id)))
          .write(changes.copyWith(generatedUntil: const Value(null)));
      await _deleteFuturePending(id, today);
    });
  }

  /// Desactiva el pago (conserva el historial) y borra sus ocurrencias pendientes futuras.
  Future<void> deactivate(int id, DateTime today) async {
    await db.transaction(() async {
      await (db.update(db.plannedPayments)..where((p) => p.id.equals(id)))
          .write(const PlannedPaymentsCompanion(active: Value(false)));
      await _deleteFuturePending(id, today);
    });
  }

  Future<void> _deleteFuturePending(int plannedId, DateTime today) => (db.delete(db.paymentOccurrences)
        ..where((o) =>
            o.plannedPaymentId.equals(plannedId) &
            o.status.equalsValue(OccurrenceStatus.pending) &
            o.dueDate.isBiggerOrEqualValue(dateOnly(today))))
      .go();

  /// Crea las ocurrencias que falten hasta hoy + [occurrenceHorizonDays] para cada pago activo.
  Future<void> ensureOccurrences(DateTime today) async {
    final t = dateOnly(today);
    final until = addDays(t, occurrenceHorizonDays);
    await db.transaction(() async {
      final planned = await (db.select(db.plannedPayments)..where((p) => p.active.equals(true))).get();
      for (final p in planned) {
        final from = p.generatedUntil != null
            ? addDays(p.generatedUntil!, 1)
            : (p.anchorDate.isAfter(t) ? p.anchorDate : t);
        if (from.isAfter(until)) continue;
        final dates = dueDatesBetween(p.frequency, p.anchorDate, from, until, weekdays: p.weekdays);
        for (final d in dates) {
          await db.into(db.paymentOccurrences).insert(
                PaymentOccurrencesCompanion.insert(plannedPaymentId: p.id, dueDate: d),
                mode: InsertMode.insertOrIgnore,
              );
        }
        await (db.update(db.plannedPayments)..where((x) => x.id.equals(p.id)))
            .write(PlannedPaymentsCompanion(generatedUntil: Value(until)));
      }
    });
  }

  JoinedSelectStatement<HasResultSet, dynamic> _joined() => db.select(db.paymentOccurrences).join([
        innerJoin(db.plannedPayments, db.plannedPayments.id.equalsExp(db.paymentOccurrences.plannedPaymentId)),
      ]);

  List<OccurrenceView> _map(List<TypedResult> rows) => [
        for (final r in rows) OccurrenceView(r.readTable(db.paymentOccurrences), r.readTable(db.plannedPayments)),
      ];

  /// Ocurrencias con vencimiento entre [from] y [to], ordenadas por fecha.
  Stream<List<OccurrenceView>> watchOccurrences(DateTime from, DateTime to) {
    final q = _joined()
      ..where(db.paymentOccurrences.dueDate.isBetweenValues(dateOnly(from), dateOnly(to)))
      ..orderBy([OrderingTerm.asc(db.paymentOccurrences.dueDate), OrderingTerm.asc(db.plannedPayments.name)]);
    return q.watch().map(_map);
  }

  /// Pendientes o pospuestas de pagos activos (las candidatas a recordatorio).
  Future<List<OccurrenceView>> openOccurrences() async {
    final q = _joined()
      ..where(db.plannedPayments.active.equals(true) &
          db.paymentOccurrences.status.isInValues([OccurrenceStatus.pending, OccurrenceStatus.snoozed]));
    return _map(await q.get());
  }

  Future<OccurrenceView?> occurrenceById(int id) async {
    final q = _joined()..where(db.paymentOccurrences.id.equals(id));
    final rows = await q.get();
    return rows.isEmpty ? null : _map(rows).single;
  }

  Future<void> setStatus(int occurrenceId, OccurrenceStatus status, {DateTime? snoozedUntil}) =>
      (db.update(db.paymentOccurrences)..where((o) => o.id.equals(occurrenceId))).write(
        PaymentOccurrencesCompanion(status: Value(status), snoozedUntil: Value(snoozedUntil)),
      );
}
