import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';

const backupAppId = 'ag_finanzas';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Exporta e importa todos los datos como JSON. La parte de archivos/compartir vive en la UI.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  Future<Map<String, dynamic>> exportData({DateTime? now}) async {
    Future<List<Map<String, dynamic>>> dump<T extends Table, D extends DataClass>(TableInfo<T, D> table) async =>
        [for (final row in await db.select(table).get()) row.toJson()];

    return {
      'app': backupAppId,
      'schemaVersion': db.schemaVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'tables': {
        'categories': await dump(db.categories),
        'goals': await dump(db.goals),
        'debts': await dump(db.debts),
        'planned_payments': await dump(db.plannedPayments),
        'payment_occurrences': await dump(db.paymentOccurrences),
        'transactions': await dump(db.transactions),
        'budgets': await dump(db.budgets),
        'app_settings': await dump(db.appSettings),
      },
    };
  }

  Future<String> exportJson({DateTime? now}) async =>
      const JsonEncoder.withIndent('  ').convert(await exportData(now: now));

  /// Valida el archivo antes de tocar nada; lanza [BackupFormatException] si no sirve.
  Map<String, dynamic> parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException('El archivo no es un respaldo válido.');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != backupAppId || decoded['tables'] is! Map) {
      throw const BackupFormatException('El archivo no es un respaldo de AG Finanzas.');
    }
    final version = decoded['schemaVersion'];
    if (version is! int || version > db.schemaVersion) {
      throw const BackupFormatException('El respaldo es de una versión más nueva de la app. Actualízala primero.');
    }
    return decoded;
  }

  /// Reemplaza todos los datos por los del respaldo en una sola transacción.
  Future<void> importData(Map<String, dynamic> data) async {
    final tables = data['tables'] as Map<String, dynamic>;
    List<Map<String, dynamic>> rows(String name) =>
        [for (final r in (tables[name] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];

    try {
      await db.transaction(() async {
        // Hijos primero al borrar, padres primero al insertar.
        for (final TableInfo table in [
          db.budgets,
          db.transactions,
          db.paymentOccurrences,
          db.plannedPayments,
          db.debts,
          db.goals,
          db.categories,
          db.appSettings,
        ]) {
          await db.delete(table).go();
        }
        await db.batch((b) {
          b.insertAll(db.categories, rows('categories').map(Category.fromJson));
          b.insertAll(db.goals, rows('goals').map(Goal.fromJson));
          b.insertAll(db.debts, rows('debts').map(Debt.fromJson));
          b.insertAll(db.plannedPayments, rows('planned_payments').map(PlannedPayment.fromJson));
          b.insertAll(db.paymentOccurrences, rows('payment_occurrences').map(PaymentOccurrence.fromJson));
          b.insertAll(db.transactions, rows('transactions').map(Txn.fromJson));
          b.insertAll(db.budgets, rows('budgets').map(Budget.fromJson));
          b.insertAll(db.appSettings, rows('app_settings').map(AppSetting.fromJson));
        });
      });
    } on BackupFormatException {
      rethrow;
    } catch (e) {
      throw BackupFormatException('No se pudo importar el respaldo: $e');
    }
  }
}
