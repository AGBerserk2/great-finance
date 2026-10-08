import 'package:ag_finanzas/app/providers.dart';
import 'package:ag_finanzas/app/theme.dart';
import 'package:ag_finanzas/data/database.dart';
import 'package:ag_finanzas/data/repositories/budgets_repository.dart';
import 'package:ag_finanzas/domain/dates.dart';
import 'package:ag_finanzas/features/budget/budget_screen.dart';
import 'package:ag_finanzas/features/transactions/transaction_sheet.dart';
import 'package:ag_finanzas/features/transactions/transactions_screen.dart';
import 'package:ag_finanzas/widgets/common.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late FakeNotifications notifications;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() {
    db = newTestDb();
    notifications = FakeNotifications();
  });

  Future<void> pumpApp(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appNotificationsProvider.overrideWithValue(notifications),
        notificationsEnabledProvider.overrideWith((ref) async => true),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// drift usa `Timer.run` internamente; bajo el reloj falso hay que bombear frames para que
  /// el cierre de la base termine.
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    final closing = db.close();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await closing;
  }

  testWidgets('registro rápido guarda un gasto con su categoría', (tester) async {
    await pumpApp(tester, const Scaffold(body: TransactionSheet()));

    await tester.enterText(find.byType(MoneyField), '1,250.50');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Comida'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    final txns = await tester.runAsync(() => db.select(db.transactions).get());
    expect(txns!.single.amountCents, 125050);
    expect(txns.single.kind, TxKind.expense);
    expect(txns.single.categoryId, await tester.runAsync(() => categoryId(db, 'Comida')));
    await disposeApp(tester);
  });

  testWidgets('registro rápido exige monto y categoría', (tester) async {
    await pumpApp(tester, const Scaffold(body: TransactionSheet()));
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe un monto válido'), findsOneWidget);
    expect(find.text('Elige una categoría'), findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.transactions).get()), isEmpty);
    await disposeApp(tester);
  });

  testWidgets('la lista de movimientos muestra el gasto del mes', (tester) async {
    final food = (await tester.runAsync(() => categoryId(db, 'Comida')))!;
    await tester.runAsync(() => db.into(db.transactions).insert(TransactionsCompanion.insert(
          kind: TxKind.expense,
          amountCents: 45000,
          categoryId: Value(food),
          date: dateOnly(DateTime.now()),
          note: const Value('Almuerzo'),
        )));
    await pumpApp(tester, const TransactionsScreen());
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('-RD\$450.00'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('las barras del presupuesto cambian de color según el %', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      final repo = BudgetsRepository(db);
      final food = await categoryId(db, 'Comida');
      final luz = await categoryId(db, 'Luz');
      final agua = await categoryId(db, 'Agua');
      await repo.setLimit(food, now, 10000);
      await repo.setLimit(luz, now, 10000);
      await repo.setLimit(agua, now, 10000);
      Future<void> spend(int cat, int cents) => db.into(db.transactions).insert(
          TransactionsCompanion.insert(kind: TxKind.expense, amountCents: cents, categoryId: Value(cat), date: dateOnly(now)));
      await spend(food, 12000);
      await spend(luz, 8500);
      await spend(agua, 1000);
    });
    await pumpApp(tester, const BudgetScreen());

    Color barColorFor(String name) {
      final card = find.ancestor(of: find.text(name), matching: find.byType(Card));
      return tester.widget<ProgressBar>(find.descendant(of: card, matching: find.byType(ProgressBar))).color;
    }

    final context = tester.element(find.byType(BudgetScreen));
    expect(barColorFor('Comida'), MoneyColors.danger(context));
    expect(barColorFor('Luz'), MoneyColors.warning(context));
    expect(barColorFor('Agua'), MoneyColors.ok(context));
    expect(find.text('120 %'), findsOneWidget);
    await disposeApp(tester);
  });
}
