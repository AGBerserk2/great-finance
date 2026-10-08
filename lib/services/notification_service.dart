import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../data/repositories/budgets_repository.dart';
import '../data/repositories/payments_repository.dart';
import '../domain/budget_status.dart';
import '../domain/money.dart';
import 'ledger.dart';
import 'notifications.dart';
import 'payment_actions.dart';
import 'payment_scheduler.dart';
import 'reminder_text.dart';

const _channelPayments = 'pagos';
const _channelBudget = 'presupuesto';
const _channelConfirm = 'confirmaciones';

const actionPaid = 'paid';
const actionNotPaid = 'not_paid';
const actionSnooze1 = 'snooze_1';
const actionSnooze3 = 'snooze_3';
const actionSkip = 'skip';

/// Los ids de notificación de pagos son los ids de ocurrencia; las alertas usan otro rango.
const _budgetAlertIdBase = 1 << 30;

const _icon = 'ic_notification';

/// Inicializa zona horaria y formatos en español. Necesario en la app y en el isolate de fondo.
Future<void> initLocaleAndTimeZone() async {
  await initializeDateFormatting('es');
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('America/Santo_Domingo'));
  }
}

class NotificationService implements AppNotifications {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;
  Future<bool>? _exactAllowed;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init({DidReceiveNotificationResponseCallback? onResponse}) async {
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings(_icon)),
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _channelPayments,
      'Pagos',
      description: 'Recordatorios de pagos planeados',
      importance: Importance.high,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _channelBudget,
      'Presupuesto',
      description: 'Avisos al llegar al 80 % y 100 % del presupuesto',
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      _channelConfirm,
      'Confirmaciones',
      description: 'Confirmación de acciones hechas desde una notificación',
      importance: Importance.low,
    ));
  }

  /// Ocurrencia cuya notificación abrió la app, si fue así.
  Future<int?> launchOccurrenceId() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return int.tryParse(details?.notificationResponse?.payload ?? '');
  }

  Future<bool> notificationsEnabled() async => await _android?.areNotificationsEnabled() ?? true;

  Future<bool> canScheduleExact() async => await _android?.canScheduleExactNotifications() ?? true;

  /// Pide permiso de notificaciones y de alarmas exactas. Devuelve si las notificaciones quedaron activas.
  Future<bool> requestPermissions() async {
    final android = _android;
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission() ?? false;
    if (!await canScheduleExact()) await android.requestExactAlarmsPermission();
    _exactAllowed = null;
    return granted;
  }

  @override
  Future<void> cancelScheduledReminders() async {
    _exactAllowed = null;
    for (final pending in await plugin.pendingNotificationRequests()) {
      await plugin.cancel(id: pending.id);
    }
  }

  @override
  Future<void> scheduleReminder(ReminderRequest r) async {
    final exact = await (_exactAllowed ??= canScheduleExact());
    await plugin.zonedSchedule(
      id: r.id,
      scheduledDate: tz.TZDateTime.from(r.when, tz.local),
      title: r.title,
      body: r.body,
      payload: '${r.id}',
      androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelPayments,
          'Pagos',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            AndroidNotificationAction(actionPaid, 'Pagué'),
            AndroidNotificationAction(actionNotPaid, 'No pagué'),
          ],
        ),
      ),
    );
  }

  /// Reemplaza la notificación del pago por la pregunta de cuándo recordar.
  Future<void> showSnoozeChooser(OccurrenceView v) => plugin.show(
        id: v.occurrence.id,
        title: '¿Cuándo te recuerdo?',
        body: reminderTitle(v),
        payload: '${v.occurrence.id}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelPayments,
            'Pagos',
            importance: Importance.high,
            priority: Priority.high,
            onlyAlertOnce: true,
            silent: true,
            actions: [
              AndroidNotificationAction(actionSnooze1, 'Mañana'),
              AndroidNotificationAction(actionSnooze3, 'En 3 días'),
              AndroidNotificationAction(actionSkip, 'No lo pagaré'),
            ],
          ),
        ),
      );

  /// Mensaje breve que desaparece solo.
  Future<void> showConfirmation(int id, String title, String body) => plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelConfirm,
            'Confirmaciones',
            importance: Importance.low,
            priority: Priority.low,
            timeoutAfter: 4000,
          ),
        ),
      );

  Future<void> showError(int id) => plugin.show(
        id: id,
        title: 'No se pudo registrar',
        body: 'Abre la app para revisar este pago.',
        payload: '$id',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(_channelPayments, 'Pagos', importance: Importance.high),
        ),
      );

  Future<void> cancel(int id) => plugin.cancel(id: id);

  @override
  Future<void> showBudgetAlert(BudgetAlert alert) => plugin.show(
        id: _budgetAlertIdBase + alert.budgetId * 2 + (alert.level == BudgetLevel.over ? 1 : 0),
        title: alert.level == BudgetLevel.over
            ? 'Te pasaste del presupuesto de ${alert.categoryName}'
            : 'Vas por el 80 % en ${alert.categoryName}',
        body: '${formatMoney(alert.spentCents)} de ${formatMoney(alert.limitCents)}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(_channelBudget, 'Presupuesto'),
        ),
      );
}

/// Ejecuta la acción tocada en una notificación. Lo usan el handler de primer plano (con la base
/// de la app) y el de segundo plano (abre su propia conexión al mismo archivo).
Future<void> handleNotificationAction(
  NotificationResponse response, {
  required AppDatabase db,
  required NotificationService service,
}) async {
  final occurrenceId = int.tryParse(response.payload ?? '');
  final action = response.actionId;
  if (occurrenceId == null || action == null) return;

  final ledger = Ledger(db, service);
  final actions = PaymentActions(db, ledger);
  final scheduler = PaymentScheduler(db, service);
  try {
    final view = await actions.payments.occurrenceById(occurrenceId);
    if (view == null) {
      await service.cancel(occurrenceId);
      return;
    }
    final label = reminderTitle(view);
    switch (action) {
      case actionPaid:
        final result = await actions.markPaid(occurrenceId);
        await service.showConfirmation(
          occurrenceId,
          result == ActionResult.alreadyPaid ? 'Ya estaba registrado' : 'Registrado ✓',
          label,
        );
      case actionNotPaid:
        await service.showSnoozeChooser(view);
        return;
      case actionSnooze1 || actionSnooze3:
        final days = action == actionSnooze1 ? 1 : 3;
        final result = await actions.snooze(occurrenceId, days);
        await service.showConfirmation(
          occurrenceId,
          result == ActionResult.alreadyPaid ? 'Ya estaba registrado' : (days == 1 ? 'Te recuerdo mañana' : 'Te recuerdo en 3 días'),
          label,
        );
      case actionSkip:
        await actions.skip(occurrenceId);
        await service.showConfirmation(occurrenceId, 'Omitido este período', label);
    }
    await scheduler.sync();
  } catch (e, s) {
    debugPrint('Error en acción de notificación: $e\n$s');
    await service.showError(occurrenceId);
  }
}

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await initLocaleAndTimeZone();
  final service = NotificationService();
  await service.init();
  final db = AppDatabase();
  try {
    await handleNotificationAction(response, db: db, service: service);
  } finally {
    await db.close();
  }
}
