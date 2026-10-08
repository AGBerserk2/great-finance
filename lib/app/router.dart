import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/budget/budget_screen.dart';
import '../features/goals_debts/goals_debts_screen.dart';
import '../features/home/home_screen.dart';
import '../features/payments/payments_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/transaction_sheet.dart';
import '../features/transactions/transactions_screen.dart';

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/movimientos', builder: (_, _) => const TransactionsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/presupuesto', builder: (_, _) => const BudgetScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/pagos', builder: (_, _) => const PaymentsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/metas', builder: (_, _) => const GoalsDebtsScreen())]),
          ],
        ),
        GoRoute(path: '/ajustes', builder: (_, _) => const SettingsScreen()),
      ],
    );

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  /// Pestañas donde el botón "+" de registro rápido se muestra (Pagos y Metas tienen su propio botón).
  static const _quickAddTabs = {0, 1, 2};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      floatingActionButton: _quickAddTabs.contains(shell.currentIndex)
          ? FloatingActionButton(
              heroTag: 'quick-add',
              tooltip: 'Registrar gasto o ingreso',
              onPressed: () => showTransactionSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Movimientos'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Presupuesto'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Pagos'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Metas'),
        ],
      ),
    );
  }
}
