import 'package:ag_finanzas/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('formatea con símbolo, miles y 2 decimales', () {
      expect(formatMoney(250000), 'RD\$2,500.00');
      expect(formatMoney(5), 'RD\$0.05');
      expect(formatMoney(0), 'RD\$0.00');
      expect(formatMoney(123456789), 'RD\$1,234,567.89');
    });

    test('negativos llevan el signo delante', () {
      expect(formatMoney(-150050), '-RD\$1,500.50');
    });
  });

  group('parseMoneyToCents', () {
    test('acepta enteros, decimales, comas y símbolo', () {
      expect(parseMoneyToCents('2500'), 250000);
      expect(parseMoneyToCents('2,500.50'), 250050);
      expect(parseMoneyToCents('2500.5'), 250050);
      expect(parseMoneyToCents(' RD\$ 1,000 '), 100000);
      expect(parseMoneyToCents('0.07'), 7);
      expect(parseMoneyToCents('.5'), 50);
    });

    test('rechaza entradas inválidas', () {
      expect(parseMoneyToCents(''), isNull);
      expect(parseMoneyToCents('abc'), isNull);
      expect(parseMoneyToCents('1.234'), isNull);
      expect(parseMoneyToCents('1.2.3'), isNull);
      expect(parseMoneyToCents('-5'), isNull);
    });
  });

  test('centsToInput da texto editable sin símbolo', () {
    expect(centsToInput(250050), '2500.50');
    expect(centsToInput(250000), '2500');
  });
}
