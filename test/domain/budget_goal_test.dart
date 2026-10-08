import 'package:ag_finanzas/domain/budget_status.dart';
import 'package:ag_finanzas/domain/goal_pace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('budgetLevel', () {
    test('umbrales 80% y 100%', () {
      expect(budgetLevel(7999, 10000), BudgetLevel.ok);
      expect(budgetLevel(8000, 10000), BudgetLevel.warning);
      expect(budgetLevel(9999, 10000), BudgetLevel.warning);
      expect(budgetLevel(10000, 10000), BudgetLevel.over);
    });
    test('límite 0', () {
      expect(budgetLevel(0, 0), BudgetLevel.ok);
      expect(budgetLevel(1, 0), BudgetLevel.over);
    });
  });

  group('monthlyNeeded', () {
    final today = DateTime(2026, 10, 8);
    test('reparte lo que falta entre los meses restantes', () {
      expect(monthlyNeeded(targetCents: 1200000, savedCents: 0, deadline: DateTime(2027, 10, 8), today: today), 100000);
    });
    test('redondea hacia arriba', () {
      expect(monthlyNeeded(targetCents: 1000, savedCents: 0, deadline: DateTime(2027, 1, 8), today: today), 334);
    });
    test('mínimo 1 mes si la fecha es este mes o ya pasó', () {
      expect(monthlyNeeded(targetCents: 5000, savedCents: 1000, deadline: DateTime(2026, 10, 30), today: today), 4000);
      expect(monthlyNeeded(targetCents: 5000, savedCents: 1000, deadline: DateTime(2026, 1, 1), today: today), 4000);
    });
    test('null sin fecha o si ya se cumplió', () {
      expect(monthlyNeeded(targetCents: 5000, savedCents: 0, deadline: null, today: today), isNull);
      expect(monthlyNeeded(targetCents: 5000, savedCents: 5000, deadline: DateTime(2027, 1, 1), today: today), isNull);
    });
  });
}
