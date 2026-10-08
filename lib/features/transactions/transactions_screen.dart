import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/database.dart';
import '../../data/repositories/transactions_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';
import 'transaction_sheet.dart';

final _kindFilterProvider = StateProvider<TxKind?>((ref) => null);

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final kind = ref.watch(_kindFilterProvider);
    final txns = ref.watch(monthTransactionsProvider((month: month, kind: kind)));
    final totals = ref.watch(monthTotalsProvider(month)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos')),
      body: Column(
        children: [
          MonthSelector(month: month, onChanged: (m) => ref.read(selectedMonthProvider.notifier).state = m),
          if (totals != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _Total(label: 'Ingresos', cents: totals.incomeCents, color: MoneyColors.income(context)),
                  _Total(label: 'Gastos', cents: totals.expenseCents, color: MoneyColors.expense(context)),
                  _Total(label: 'Ahorro', cents: totals.savingCents, color: MoneyColors.saving(context)),
                ],
              ),
            ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final (label, value) in const [
                  ('Todos', null),
                  ('Gastos', TxKind.expense),
                  ('Ingresos', TxKind.income),
                  ('Ahorros', TxKind.saving),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: kind == value,
                      onSelected: (_) => ref.read(_kindFilterProvider.notifier).state = value,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: txns.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => list.isEmpty
                  ? const EmptyState(icon: Icons.receipt_long, message: 'No hay movimientos este mes.\nToca + para registrar uno.')
                  : _GroupedList(items: list),
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.cents, required this.color});
  final String label;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          FittedBox(
            child: Text(formatMoney(cents), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.items});
  final List<TxnWithCategory> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = {for (final g in ref.watch(activeGoalsProvider).valueOrNull ?? const <Goal>[]) g.id: g.name};
    final debts = {for (final d in ref.watch(debtsProvider).valueOrNull ?? const <Debt>[]) d.id: d.name};
    final today = DateTime.now();
    final rows = <Widget>[];
    DateTime? currentDay;
    for (final item in items) {
      final day = dateOnly(item.txn.date);
      if (day != currentDay) {
        currentDay = day;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(formatDayHeader(day, today), style: Theme.of(context).textTheme.labelLarge),
        ));
      }
      rows.add(TransactionTile(item: item, goalName: goals[item.txn.goalId], debtName: debts[item.txn.debtId]));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: rows);
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.item, this.goalName, this.debtName});
  final TxnWithCategory item;
  final String? goalName;
  final String? debtName;

  @override
  Widget build(BuildContext context) {
    final t = item.txn;
    final (sign, color) = switch (t.kind) {
      TxKind.income => ('+', MoneyColors.income(context)),
      TxKind.expense => ('-', MoneyColors.expense(context)),
      TxKind.saving => ('', MoneyColors.saving(context)),
    };
    final title = switch (t.kind) {
      TxKind.saving => 'Ahorro · ${goalName ?? 'Meta'}',
      _ when t.debtId != null => 'Pago · ${debtName ?? 'Deuda'}',
      _ => item.category?.name ?? 'Sin categoría',
    };
    return ListTile(
      leading: CategoryAvatar(category: item.category),
      title: Text(title),
      subtitle: t.note == null ? null : Text(t.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '$sign${formatMoney(t.amountCents)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: () => showTransactionSheet(context, existing: t),
    );
  }
}
