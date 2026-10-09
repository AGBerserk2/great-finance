// Genera capturas PNG de cada pantalla con fuentes reales para revisar el diseño a ojo.
// Uso: SCREENSHOTS=/ruta/salida flutter test test/visual/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ag_finanzas/app/providers.dart';
import 'package:ag_finanzas/app/router.dart';
import 'package:ag_finanzas/app/theme.dart';
import 'package:ag_finanzas/features/payments/planned_payment_form.dart';
import 'package:ag_finanzas/features/settings/settings_screen.dart';
import 'package:ag_finanzas/features/transactions/transaction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/seed.dart';
import '../helpers/test_db.dart';

final _out = Platform.environment['SCREENSHOTS'];

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(read(f));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'))).load();
}

void main() {
  const configs = [(Size(360, 780), 1.0), (Size(360, 780), 1.3), (Size(320, 640), 1.0)];

  setUpAll(() async {
    await initializeDateFormatting('es');
    if (_out != null) await _loadFonts();
  });

  for (final (size, scale) in configs) {
    testWidgets('capturas ${size.width.toInt()}x${size.height.toInt()} x$scale', skip: _out == null, (tester) async {
      final db = newTestDb();
      await tester.runAsync(() => seedRealisticData(db));
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final boundary = GlobalKey();
      final overrides = [
        databaseProvider.overrideWithValue(db),
        appNotificationsProvider.overrideWithValue(FakeNotifications()),
        notificationsEnabledProvider.overrideWith((ref) async => true),
      ];
      Widget wrap(Widget app) =>
          RepaintBoundary(key: boundary, child: ProviderScope(overrides: overrides, child: app));
      MaterialApp material({Widget? home}) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: home,
          );

      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          return image.toByteData(format: ui.ImageByteFormat.png);
        });
        final file = File('$_out/${size.width.toInt()}x${size.height.toInt()}_x${scale}_$name.png')..createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      }

      final router = buildRouter();
      await tester.pumpWidget(wrap(MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      )));
      await shot('1_inicio');
      for (final (route, name) in [('/movimientos', '2_movimientos'), ('/presupuesto', '3_presupuesto'), ('/pagos', '4_pagos'), ('/metas', '5_metas')]) {
        router.go(route);
        await shot(name);
      }
      await tester.tap(find.text('Deudas'));
      await shot('6_deudas');

      for (final (widget, name) in <(Widget, String)>[
        (const SettingsScreen(), '7_ajustes'),
        (const Scaffold(body: TransactionSheet()), '8_registro'),
        (const PlannedPaymentForm(), '9_pago_form'),
      ]) {
        await tester.pumpWidget(wrap(material(home: widget)));
        await shot(name);
      }
      await tester.tap(find.text('Diario'));
      await shot('10_pago_diario');

      await tester.pumpWidget(const SizedBox());
      final closing = db.close();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await closing;
    });
  }
}
