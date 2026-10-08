import 'package:intl/intl.dart';

final _format = NumberFormat('#,##0.00', 'en_US');

/// Formatea centavos como `RD$2,500.00`.
String formatMoney(int cents) {
  final text = 'RD\$${_format.format(cents.abs() / 100)}';
  return cents < 0 ? '-$text' : text;
}

final _amountPattern = RegExp(r'^(\d*)(?:\.(\d{1,2}))?$');

/// Convierte lo que escribe el usuario a centavos. Devuelve `null` si no es un monto válido.
int? parseMoneyToCents(String input) {
  final cleaned = input.replaceAll('RD\$', '').replaceAll(',', '').replaceAll(' ', '').trim();
  final match = _amountPattern.firstMatch(cleaned);
  if (cleaned.isEmpty || match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  return int.parse(whole.isEmpty ? '0' : whole) * 100 + (fraction.isEmpty ? 0 : int.parse(fraction.padRight(2, '0')));
}

/// Texto editable para un campo de monto (`2500.50`, o `2500` si no tiene centavos).
String centsToInput(int cents) {
  final whole = cents ~/ 100;
  final fraction = cents % 100;
  return fraction == 0 ? '$whole' : '$whole.${fraction.toString().padLeft(2, '0')}';
}
