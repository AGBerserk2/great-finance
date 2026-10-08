import 'dates.dart';

enum DebtStatus { paid, ok, paymentTooLow, tooLong }

class DebtProjection {
  const DebtProjection({required this.status, this.months = 0, this.totalInterestCents = 0, this.payoffDate});

  final DebtStatus status;
  final int months;
  final int totalInterestCents;
  final DateTime? payoffDate;
}

const _maxMonths = 600;

/// Simula la deuda mes a mes: se suma el interés del mes y luego se resta la cuota.
DebtProjection projectDebt({
  required int balanceCents,
  required double annualRatePct,
  required int monthlyPaymentCents,
  required DateTime today,
}) {
  if (balanceCents <= 0) return DebtProjection(status: DebtStatus.paid, payoffDate: dateOnly(today));
  if (monthlyPaymentCents <= 0) return const DebtProjection(status: DebtStatus.paymentTooLow);

  final monthlyRate = annualRatePct / 12 / 100;
  var balance = balanceCents;
  var totalInterest = 0;
  var months = 0;
  while (balance > 0) {
    if (months == _maxMonths) return const DebtProjection(status: DebtStatus.tooLong);
    final interest = (balance * monthlyRate).round();
    if (months == 0 && monthlyPaymentCents <= interest) {
      return const DebtProjection(status: DebtStatus.paymentTooLow);
    }
    balance += interest;
    totalInterest += interest;
    balance -= monthlyPaymentCents < balance ? monthlyPaymentCents : balance;
    months++;
  }
  return DebtProjection(
    status: DebtStatus.ok,
    months: months,
    totalInterestCents: totalInterest,
    payoffDate: addMonths(dateOnly(today), months),
  );
}
