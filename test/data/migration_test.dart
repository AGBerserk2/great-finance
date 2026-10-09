import 'dart:io';

import 'package:ag_finanzas/data/database.dart';
import 'package:ag_finanzas/domain/recurrence.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migra una base v1 (sin weekdays) a v2 conservando los pagos', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('agfin');
    final file = File('${dir.path}/db.sqlite');

    // Crea la base actual con un pago y la "baja" a v1 quitando la columna nueva.
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.plannedPayments).insert(PlannedPaymentsCompanion.insert(
          name: 'Luz',
          amountCents: 250000,
          frequency: Frequency.monthly,
          anchorDate: DateTime(2026, 10, 10),
          remindHour: 9,
          remindMinute: 0,
        ));
    await db.close();
    db = AppDatabase(NativeDatabase(file, setup: (raw) {
      if (raw.userVersion == 2) {
        raw.execute('ALTER TABLE planned_payments DROP COLUMN weekdays');
        raw.userVersion = 1;
      }
    }));

    final payments = await db.select(db.plannedPayments).get();
    expect(payments.single.name, 'Luz');
    expect(payments.single.weekdays, weekdaysAll);
    await db.close();
    await dir.delete(recursive: true);
  });
}
