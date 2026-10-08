/// Utilidades de fechas sin hora (medianoche local).
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Suma meses manteniendo el día; si el mes destino es más corto usa su último día.
DateTime addMonths(DateTime d, int months) {
  final first = DateTime(d.year, d.month + months, 1);
  final day = d.day.clamp(1, lastDayOfMonth(first.year, first.month));
  return DateTime(first.year, first.month, day);
}

/// Clave de mes `YYYY-MM`.
String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime monthStart(DateTime d) => DateTime(d.year, d.month, 1);

/// Primer día del mes siguiente (límite exclusivo del mes de [d]).
DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1, 1);
