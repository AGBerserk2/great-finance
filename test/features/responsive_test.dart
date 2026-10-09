import 'package:ag_finanzas/app/providers.dart';
import 'package:ag_finanzas/app/router.dart';
import 'package:ag_finanzas/app/theme.dart';
import 'package:ag_finanzas/features/payments/planned_payment_form.dart';
import 'package:ag_finanzas/features/settings/categories_screen.dart';
import 'package:ag_finanzas/features/settings/settings_screen.dart';
import 'package:ag_finanzas/features/transactions/transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/seed.dart';
import '../helpers/test_db.dart';

/// Tamaños de pantalla (dp) y escalas de letra del sistema que debe aguantar la app.
const _sizes = [Size(320, 640), Size(360, 780), Size(411, 891)];
const _textScales = [1.0, 1.3, 1.6];

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  for (final size in _sizes) {
    for (final scale in _textScales) {
      // En la pantalla más chica solo exigimos hasta 1.3 de letra.
      if (size.width < 360 && scale > 1.3) continue;

      testWidgets('sin desbordes en ${size.width.toInt()}x${size.height.toInt()} letra x$scale', (tester) async {
        final db = newTestDb();
        await tester.runAsync(() => seedRealisticData(db));

        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final errors = <String>[];
        var current = 'inicio';
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          final where = RegExp(r'lib/[\w/]+\.dart:\d+').allMatches(details.toString()).map((m) => m.group(0)).toSet().join(' ');
          errors.add('[$current] ${details.exceptionAsString().split('\n').first} @ $where');
        };

        Widget app(Widget home) => ProviderScope(
              overrides: [
                databaseProvider.overrideWithValue(db),
                appNotificationsProvider.overrideWithValue(FakeNotifications()),
                notificationsEnabledProvider.overrideWith((ref) async => false),
              ],
              child: MaterialApp(
                theme: buildTheme(Brightness.light),
                locale: const Locale('es'),
                supportedLocales: const [Locale('es')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: home,
              ),
            );

        final router = buildRouter();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appNotificationsProvider.overrideWithValue(FakeNotifications()),
            notificationsEnabledProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp.router(
            theme: buildTheme(Brightness.light),
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: router,
          ),
        ));
        await tester.pumpAndSettle();
        for (final route in ['/movimientos', '/presupuesto', '/pagos', '/metas']) {
          current = route;
          router.go(route);
          await tester.pumpAndSettle();
        }
        // Pestaña de deudas.
        current = 'deudas';
        await tester.tap(find.text('Deudas'));
        await tester.pumpAndSettle();

        for (final screen in <Widget>[
          const SettingsScreen(),
          const CategoriesScreen(),
          const Scaffold(body: TransactionSheet()),
          const PlannedPaymentForm(),
        ]) {
          current = screen.runtimeType.toString() == 'Scaffold' ? 'TransactionSheet' : screen.runtimeType.toString();
          await tester.pumpWidget(app(screen));
          await tester.pumpAndSettle();
        }

        await tester.pumpWidget(const SizedBox());
        final closing = db.close();
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await closing;
        FlutterError.onError = previous;
        expect(errors.toSet().toList(), isEmpty);
      });
    }
  }
}
