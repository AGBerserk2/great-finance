import 'dates.dart';

enum Frequency { once, weekly, biweekly, monthly }

/// Fechas de vencimiento de una regla dentro de [from]..[to] (ambos inclusive, sin hora).
/// Nunca devuelve fechas anteriores a [anchor].
List<DateTime> dueDatesBetween(Frequency frequency, DateTime anchor, DateTime from, DateTime to) {
  final start = dateOnly(anchor);
  final lower = dateOnly(from).isAfter(start) ? dateOnly(from) : start;
  final upper = dateOnly(to);
  bool inRange(DateTime d) => !d.isBefore(lower) && !d.isAfter(upper);

  final result = <DateTime>[];
  switch (frequency) {
    case Frequency.once:
      if (inRange(start)) result.add(start);
    case Frequency.weekly:
      for (var d = start; !d.isAfter(upper); d = addDays(d, 7)) {
        if (inRange(d)) result.add(d);
      }
    case Frequency.biweekly:
      for (var m = DateTime(lower.year, lower.month); !m.isAfter(upper); m = DateTime(m.year, m.month + 1)) {
        for (final day in [15, lastDayOfMonth(m.year, m.month)]) {
          final d = DateTime(m.year, m.month, day);
          if (inRange(d)) result.add(d);
        }
      }
    case Frequency.monthly:
      for (var i = 0;; i++) {
        final d = addMonths(start, i);
        if (d.isAfter(upper)) break;
        if (inRange(d)) result.add(d);
      }
  }
  return result;
}
