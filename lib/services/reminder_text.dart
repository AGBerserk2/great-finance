import 'package:intl/intl.dart';

import '../data/repositories/payments_repository.dart';
import '../domain/dates.dart';
import '../domain/money.dart';

/// Requiere `initializeDateFormatting('es')`.
String reminderTitle(OccurrenceView v) => '${v.payment.name} · ${formatMoney(v.payment.amountCents)}';

/// Texto relativo a la fecha en que se muestra el recordatorio.
String reminderBody(OccurrenceView v, DateTime shownAt) {
  final due = v.occurrence.dueDate;
  final days = dateOnly(due).difference(dateOnly(shownAt)).inHours ~/ 24;
  final dateText = DateFormat('EEE d MMM', 'es').format(due).replaceAll('.', '');
  if (days == 0) return 'Vence hoy';
  if (days == 1) return 'Vence mañana';
  if (days > 1) return 'Vence el $dateText';
  return 'Venció el $dateText';
}
