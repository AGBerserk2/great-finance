import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'data/database.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initLocaleAndTimeZone();

  final db = AppDatabase();
  final notifications = NotificationService();
  late final GoRouter router;

  await notifications.init(
    onResponse: (response) async {
      if (response.actionId == null) {
        router.go('/pagos');
        return;
      }
      await handleNotificationAction(response, db: db, service: notifications);
    },
  );
  final launchedFromNotification = await notifications.launchOccurrenceId() != null;
  router = buildRouter(initialLocation: launchedFromNotification ? '/pagos' : '/');

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(notifications),
    ],
    child: FinanzasApp(router: router),
  ));
}
