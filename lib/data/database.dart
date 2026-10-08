import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/recurrence.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

const databaseName = 'ag_finanzas';

/// Categorías iniciales: (nombre, ícono, color, tipo).
const defaultCategories = <(String, String, int, CategoryKind)>[
  ('Comida', 'restaurant', 0xFFE57373, CategoryKind.expense),
  ('Supermercado', 'shopping_cart', 0xFF81C784, CategoryKind.expense),
  ('Transporte', 'directions_bus', 0xFF64B5F6, CategoryKind.expense),
  ('Combustible', 'local_gas_station', 0xFFFFB74D, CategoryKind.expense),
  ('Alquiler', 'home', 0xFFA1887F, CategoryKind.expense),
  ('Luz', 'bolt', 0xFFFFD54F, CategoryKind.expense),
  ('Agua', 'water_drop', 0xFF4FC3F7, CategoryKind.expense),
  ('Internet y teléfono', 'wifi', 0xFF9575CD, CategoryKind.expense),
  ('Salud', 'local_hospital', 0xFFF06292, CategoryKind.expense),
  ('Educación', 'school', 0xFF4DB6AC, CategoryKind.expense),
  ('Entretenimiento', 'movie', 0xFFBA68C8, CategoryKind.expense),
  ('Ropa', 'checkroom', 0xFF7986CB, CategoryKind.expense),
  ('Deudas', 'credit_card', 0xFFE53935, CategoryKind.expense),
  ('Otros', 'more_horiz', 0xFF90A4AE, CategoryKind.expense),
  ('Sueldo', 'payments', 0xFF43A047, CategoryKind.income),
  ('Extra', 'add_card', 0xFF00897B, CategoryKind.income),
  ('Otros ingresos', 'savings', 0xFF7CB342, CategoryKind.income),
];

@DriftDatabase(tables: [Categories, Goals, Debts, PlannedPayments, PaymentOccurrences, Transactions, Budgets, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await batch((b) {
            b.insertAll(categories, [
              for (final (name, icon, color, kind) in defaultCategories)
                CategoriesCompanion.insert(name: name, icon: icon, color: color, kind: kind),
            ]);
          });
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Abre el archivo de la app. La app y el handler de notificaciones en segundo plano
  /// abren cada uno su conexión al mismo archivo; WAL y busy_timeout evitan bloqueos.
  static QueryExecutor openConnection() => driftDatabase(
        name: databaseName,
        native: const DriftNativeOptions(setup: _setupConnection),
      );

  /// Fuerza a que todas las consultas reactivas se vuelvan a ejecutar (p. ej. tras cambios
  /// hechos por el handler de notificaciones en otra conexión).
  void refreshAll() => markTablesUpdated(allTables);

  Future<String?> getSetting(String key) async =>
      (await (select(appSettings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}

void _setupConnection(dynamic db) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA busy_timeout = 5000');
}
