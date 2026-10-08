import 'package:intl/intl.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "Octubre 2026"
String formatMonth(DateTime d) => _cap(DateFormat('MMMM yyyy', 'es').format(d));

/// "10 oct"
String formatShortDate(DateTime d) => DateFormat('d MMM', 'es').format(d).replaceAll('.', '');

/// "jueves 10 de octubre"
String formatLongDate(DateTime d) => DateFormat("EEEE d 'de' MMMM", 'es').format(d);

/// "oct 2027"
String formatMonthShort(DateTime d) => DateFormat('MMM yyyy', 'es').format(d).replaceAll('.', '');

String formatTime(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'a. m.' : 'p. m.'}';
}

/// Título de grupo de días: "Hoy", "Ayer" o "jueves 10 de octubre".
String formatDayHeader(DateTime d, DateTime today) {
  final diff = DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inHours ~/ 24;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  return _cap(formatLongDate(d));
}
