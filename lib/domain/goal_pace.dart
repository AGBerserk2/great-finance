/// Cuánto hay que ahorrar al mes para llegar a la meta en la fecha límite.
/// `null` si no hay fecha límite o la meta ya se cumplió.
int? monthlyNeeded({
  required int targetCents,
  required int savedCents,
  required DateTime? deadline,
  required DateTime today,
}) {
  final remaining = targetCents - savedCents;
  if (deadline == null || remaining <= 0) return null;
  var months = (deadline.year - today.year) * 12 + deadline.month - today.month;
  if (months < 1) months = 1;
  return (remaining + months - 1) ~/ months;
}
