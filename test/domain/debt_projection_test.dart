import 'package:ag_finanzas/domain/debt_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 8);

  test('tasa 0: meses = saldo / cuota, sin interés', () {
    final p = projectDebt(balanceCents: 100000, annualRatePct: 0, monthlyPaymentCents: 30000, today: today);
    expect(p.status, DebtStatus.ok);
    expect(p.months, 4);
    expect(p.totalInterestCents, 0);
    expect(p.payoffDate, DateTime(2027, 2, 8));
  });

  test('con interés: simula mes a mes', () {
    // 10,000 al 24% anual (2% mensual), cuota 5,000.
    // m1: 10000+200=10200-5000=5200; m2: 5200+104=5304-5000=304; m3: 304+6.08→6 =310 -> 0
    final p = projectDebt(balanceCents: 1000000, annualRatePct: 24, monthlyPaymentCents: 500000, today: today);
    expect(p.status, DebtStatus.ok);
    expect(p.months, 3);
    expect(p.totalInterestCents, 20000 + 10400 + 608);
  });

  test('cuota que no cubre el interés', () {
    final p = projectDebt(balanceCents: 10000000, annualRatePct: 60, monthlyPaymentCents: 400000, today: today);
    expect(p.status, DebtStatus.paymentTooLow);
  });

  test('saldo 0: ya está pagada', () {
    final p = projectDebt(balanceCents: 0, annualRatePct: 20, monthlyPaymentCents: 1000, today: today);
    expect(p.status, DebtStatus.paid);
    expect(p.months, 0);
  });

  test('más de 600 meses se reporta como demasiado larga', () {
    final p = projectDebt(balanceCents: 100000000, annualRatePct: 0, monthlyPaymentCents: 100, today: today);
    expect(p.status, DebtStatus.tooLong);
  });

  test('payoffDate ajusta al último día del mes', () {
    final p = projectDebt(balanceCents: 100, annualRatePct: 0, monthlyPaymentCents: 100, today: DateTime(2026, 1, 31));
    expect(p.payoffDate, DateTime(2026, 2, 28));
  });
}
