import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repositories/budgets_repository.dart';
import '../data/repositories/categories_repository.dart';
import '../data/repositories/debts_repository.dart';
import '../data/repositories/goals_repository.dart';
import '../data/repositories/payments_repository.dart';
import '../data/repositories/transactions_repository.dart';
import '../domain/dates.dart';
import '../services/backup_service.dart';
import '../services/ledger.dart';
import '../services/notification_service.dart';
import '../services/notifications.dart';
import '../services/payment_actions.dart';
import '../services/payment_scheduler.dart';

/// Se sobreescriben en `main()`.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final notificationServiceProvider = Provider<NotificationService>((ref) => throw UnimplementedError());

/// Lo que usa la lógica (alertas y recordatorios). En tests se sobreescribe con un fake.
final appNotificationsProvider = Provider<AppNotifications>((ref) => ref.watch(notificationServiceProvider));

final categoriesRepoProvider = Provider((ref) => CategoriesRepository(ref.watch(databaseProvider)));
final transactionsRepoProvider = Provider((ref) => TransactionsRepository(ref.watch(databaseProvider)));
final budgetsRepoProvider = Provider((ref) => BudgetsRepository(ref.watch(databaseProvider)));
final paymentsRepoProvider = Provider((ref) => PaymentsRepository(ref.watch(databaseProvider)));
final goalsRepoProvider = Provider((ref) => GoalsRepository(ref.watch(databaseProvider)));
final debtsRepoProvider = Provider((ref) => DebtsRepository(ref.watch(databaseProvider)));

final ledgerProvider = Provider((ref) => Ledger(ref.watch(databaseProvider), ref.watch(appNotificationsProvider)));
final paymentActionsProvider = Provider((ref) => PaymentActions(ref.watch(databaseProvider), ref.watch(ledgerProvider)));
final schedulerProvider =
    Provider((ref) => PaymentScheduler(ref.watch(databaseProvider), ref.watch(appNotificationsProvider)));
final backupServiceProvider = Provider((ref) => BackupService(ref.watch(databaseProvider)));

/// Mes seleccionado en Movimientos y Presupuesto (primer día del mes).
final selectedMonthProvider = StateProvider<DateTime>((ref) => monthStart(DateTime.now()));

final categoriesProvider = StreamProvider.family<List<Category>, CategoryKind?>(
  (ref, kind) => ref.watch(categoriesRepoProvider).watch(kind: kind),
);

final monthTotalsProvider = StreamProvider.family<MonthTotals, DateTime>(
  (ref, month) => ref.watch(transactionsRepoProvider).watchTotals(month),
);

typedef TxFilter = ({DateTime month, TxKind? kind});

final monthTransactionsProvider = StreamProvider.family<List<TxnWithCategory>, TxFilter>(
  (ref, f) => ref.watch(transactionsRepoProvider).watchMonth(f.month, kind: f.kind),
);

final budgetLinesProvider = StreamProvider.family<List<BudgetLine>, DateTime>(
  (ref, month) => ref.watch(budgetsRepoProvider).watchMonth(month),
);

final plannedPaymentsProvider = StreamProvider((ref) => ref.watch(paymentsRepoProvider).watchPlanned());

/// Ocurrencias de 60 días atrás a 60 días adelante.
final occurrencesProvider = StreamProvider((ref) {
  final today = dateOnly(DateTime.now());
  return ref.watch(paymentsRepoProvider).watchOccurrences(addDays(today, -60), addDays(today, 60));
});

final goalsProvider = StreamProvider((ref) => ref.watch(goalsRepoProvider).watch());
final activeGoalsProvider = StreamProvider((ref) => ref.watch(goalsRepoProvider).watchActive());
final debtsProvider = StreamProvider((ref) => ref.watch(debtsRepoProvider).watch());

/// Estado de permisos; se invalida al volver a la app.
final notificationsEnabledProvider =
    FutureProvider((ref) => ref.watch(notificationServiceProvider).notificationsEnabled());
