import '../data/database.dart';
import '../data/repositories/payments_repository.dart';
import '../domain/dates.dart';
import 'notifications.dart';
import 'reminder_text.dart';

/// Android limita las alarmas por app (~500); dejamos margen.
const maxScheduledReminders = 400;

/// Próximo momento en que debe sonar el recordatorio de [v], o `null` si ya no queda ninguno.
/// Pendiente: X días antes del vencimiento y, si ese ya pasó, el mismo día del vencimiento.
/// Pospuesto: el día pospuesto. Siempre a la hora configurada en el pago.
DateTime? reminderTimeFor(OccurrenceView v, DateTime now) {
  final p = v.payment;
  DateTime at(DateTime d) => DateTime(d.year, d.month, d.day, p.remindHour, p.remindMinute);
  final candidates = switch (v.occurrence.status) {
    OccurrenceStatus.snoozed => [at(v.occurrence.snoozedUntil!)],
    OccurrenceStatus.pending => [at(addDays(v.occurrence.dueDate, -p.remindDaysBefore)), at(v.occurrence.dueDate)],
    _ => const <DateTime>[],
  };
  for (final c in candidates) {
    if (c.isAfter(now)) return c;
  }
  return null;
}

class PaymentScheduler {
  PaymentScheduler(this.db, this.notifications, {DateTime Function()? clock})
      : payments = PaymentsRepository(db),
        _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final AppNotifications notifications;
  final PaymentsRepository payments;
  final DateTime Function() _clock;

  /// Genera ocurrencias faltantes y reprograma todos los recordatorios.
  Future<void> sync() async {
    final now = _clock();
    await payments.ensureOccurrences(now);
    final requests = <ReminderRequest>[];
    for (final v in await payments.openOccurrences()) {
      final when = reminderTimeFor(v, now);
      if (when == null) continue;
      requests.add(ReminderRequest(id: v.occurrence.id, title: reminderTitle(v), body: reminderBody(v, when), when: when));
    }
    requests.sort((a, b) => a.when.compareTo(b.when));
    await notifications.cancelScheduledReminders();
    for (final r in requests.take(maxScheduledReminders)) {
      await notifications.scheduleReminder(r);
    }
  }
}
