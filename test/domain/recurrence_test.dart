import 'package:ag_finanzas/domain/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  test('once: solo la fecha ancla si cae en el rango', () {
    expect(dueDatesBetween(Frequency.once, d(2026, 10, 20), d(2026, 10, 1), d(2026, 10, 31)), [d(2026, 10, 20)]);
    expect(dueDatesBetween(Frequency.once, d(2026, 9, 20), d(2026, 10, 1), d(2026, 10, 31)), isEmpty);
  });

  test('weekly: cada 7 días desde el ancla', () {
    expect(
      dueDatesBetween(Frequency.weekly, d(2026, 9, 28), d(2026, 10, 1), d(2026, 10, 20)),
      [d(2026, 10, 5), d(2026, 10, 12), d(2026, 10, 19)],
    );
  });

  test('biweekly: días 15 y último de cada mes, desde el ancla', () {
    expect(
      dueDatesBetween(Frequency.biweekly, d(2026, 1, 20), d(2026, 1, 1), d(2026, 3, 20)),
      [d(2026, 1, 31), d(2026, 2, 15), d(2026, 2, 28), d(2026, 3, 15)],
    );
  });

  test('biweekly en año bisiesto usa 29 de febrero', () {
    expect(
      dueDatesBetween(Frequency.biweekly, d(2028, 2, 1), d(2028, 2, 1), d(2028, 2, 29)),
      [d(2028, 2, 15), d(2028, 2, 29)],
    );
  });

  test('monthly: día 31 cae en el último día de meses cortos', () {
    expect(
      dueDatesBetween(Frequency.monthly, d(2026, 1, 31), d(2026, 1, 1), d(2026, 4, 30)),
      [d(2026, 1, 31), d(2026, 2, 28), d(2026, 3, 31), d(2026, 4, 30)],
    );
  });

  test('monthly: no genera fechas antes del ancla', () {
    expect(
      dueDatesBetween(Frequency.monthly, d(2026, 10, 10), d(2026, 9, 1), d(2026, 11, 30)),
      [d(2026, 10, 10), d(2026, 11, 10)],
    );
  });

  test('ignora la hora de los parámetros', () {
    expect(
      dueDatesBetween(Frequency.once, DateTime(2026, 10, 5, 18), DateTime(2026, 10, 5, 23), DateTime(2026, 10, 5, 1)),
      [d(2026, 10, 5)],
    );
  });

  group('daily', () {
    test('todos los días por defecto', () {
      expect(
        dueDatesBetween(Frequency.daily, d(2026, 10, 8), d(2026, 10, 1), d(2026, 10, 11)),
        [d(2026, 10, 8), d(2026, 10, 9), d(2026, 10, 10), d(2026, 10, 11)],
      );
    });

    test('solo los días marcados (lunes a viernes)', () {
      // 2026-10-08 es jueves; 10 y 11 son sábado y domingo.
      expect(
        dueDatesBetween(Frequency.daily, d(2026, 10, 8), d(2026, 10, 8), d(2026, 10, 13), weekdays: weekdaysMonToFri),
        [d(2026, 10, 8), d(2026, 10, 9), d(2026, 10, 12), d(2026, 10, 13)],
      );
    });

    test('máscara vacía no genera nada', () {
      expect(dueDatesBetween(Frequency.daily, d(2026, 10, 8), d(2026, 10, 8), d(2026, 10, 20), weekdays: 0), isEmpty);
    });
  });

  test('weekdayBit y nombres', () {
    expect(weekdayBit(DateTime.monday), 1);
    expect(weekdayBit(DateTime.sunday), 64);
    expect(weekdaysAll, 127);
    expect(weekdaysLabel(weekdaysAll), 'Todos los días');
    expect(weekdaysLabel(weekdaysMonToFri), 'Lunes a viernes');
    expect(weekdaysLabel(weekdayBit(DateTime.monday) | weekdayBit(DateTime.wednesday)), 'Lun, Mié');
  });
}
