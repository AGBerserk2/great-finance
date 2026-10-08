import '../data/repositories/budgets_repository.dart';

class ReminderRequest {
  const ReminderRequest({required this.id, required this.title, required this.body, required this.when});
  final int id;
  final String title;
  final String body;
  final DateTime when;
}

/// Lo que la lógica de la app necesita de las notificaciones. La implementación real es
/// `NotificationService`; en los tests se usa un fake.
abstract interface class AppNotifications {
  Future<void> showBudgetAlert(BudgetAlert alert);

  /// Cancela los recordatorios de pagos programados (no los que ya están visibles).
  Future<void> cancelScheduledReminders();

  Future<void> scheduleReminder(ReminderRequest request);
}
