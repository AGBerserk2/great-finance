import 'dates.dart';

enum Frequency { once, daily, weekly, biweekly, monthly }

/// Días de la semana como máscara de bits: lunes = 1 … domingo = 64.
int weekdayBit(int weekday) => 1 << (weekday - 1);

const weekdaysAll = 127;
const weekdaysMonToFri = 31;

const _shortNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

String weekdaysLabel(int mask) {
  if (mask & weekdaysAll == weekdaysAll) return 'Todos los días';
  if (mask & weekdaysAll == weekdaysMonToFri) return 'Lunes a viernes';
  if (mask & weekdaysAll == 96) return 'Fines de semana';
  return [for (var i = 0; i < 7; i++) if (mask & (1 << i) != 0) _shortNames[i]].join(', ');
}

/// Fechas de vencimiento de una regla dentro de [from]..[to] (ambos inclusive, sin hora).
/// Nunca devuelve fechas anteriores a [anchor]. [weekdays] solo aplica a `daily`.
List<DateTime> dueDatesBetween(
  Frequency frequency,
  DateTime anchor,
  DateTime from,
  DateTime to, {
  int weekdays = weekdaysAll,
}) {
  final start = dateOnly(anchor);
  final lower = dateOnly(from).isAfter(start) ? dateOnly(from) : start;
  final upper = dateOnly(to);
  bool inRange(DateTime d) => !d.isBefore(lower) && !d.isAfter(upper);

  final result = <DateTime>[];
  switch (frequency) {
    case Frequency.once:
      if (inRange(start)) result.add(start);
    case Frequency.daily:
      for (var d = lower; !d.isAfter(upper); d = addDays(d, 1)) {
        if (weekdays & weekdayBit(d.weekday) != 0) result.add(d);
      }
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
