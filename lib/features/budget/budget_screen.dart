import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../data/repositories/budgets_repository.dart';
import '../../domain/budget_status.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';

/// Copia los límites del mes anterior la primera vez que se abre un mes.
final _ensureMonthProvider = FutureProvider.family<void, DateTime>(
  (ref, month) => ref.read(budgetsRepoProvider).ensureMonth(month),
);

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    ref.watch(_ensureMonthProvider(month));
    final lines = ref.watch(budgetLinesProvider(month));

    return Scaffold(
      appBar: AppBar(title: const Text('Presupuesto')),
      body: lines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final withLimit = list.where((l) => l.limitCents != null).toList()
            ..sort((a, b) => b.ratio.compareTo(a.ratio));
          final withoutLimit = list.where((l) => l.limitCents == null).toList();
          final totalLimit = withLimit.fold<int>(0, (s, l) => s + l.limitCents!);
          final totalSpent = withLimit.fold<int>(0, (s, l) => s + l.spentCents);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              MonthSelector(month: month, onChanged: (m) => ref.read(selectedMonthProvider.notifier).state = m),
              if (withLimit.isNotEmpty) _Summary(spent: totalSpent, limit: totalLimit),
              if (withLimit.isEmpty)
                const EmptyState(
                  icon: Icons.pie_chart_outline,
                  message: 'Aún no tienes límites este mes.\nToca una categoría abajo para fijar cuánto quieres gastar.',
                ),
              if (withLimit.isNotEmpty) const SectionHeader('Con límite'),
              for (final l in withLimit) _BudgetTile(line: l, month: month),
              if (withoutLimit.isNotEmpty) const SectionHeader('Sin límite'),
              for (final l in withoutLimit) _BudgetTile(line: l, month: month),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.spent, required this.limit});
  final int spent;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final level = budgetLevel(spent, limit);
    final left = limit - spent;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(left >= 0 ? 'Te quedan' : 'Te pasaste por', style: theme.textTheme.labelLarge),
            Text(formatMoney(left.abs()), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ProgressBar(value: limit == 0 ? 0 : spent / limit, color: levelColor(context, level), height: 10),
            const SizedBox(height: 8),
            Text('${formatMoney(spent)} gastado de ${formatMoney(limit)}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BudgetTile extends ConsumerWidget {
  const _BudgetTile({required this.line, required this.month});
  final BudgetLine line;
  final DateTime month;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(budgetsRepoProvider);
    final hasLimit = line.limitCents != null;
    final cents = await askAmount(
      context,
      title: 'Límite de ${line.category.name}',
      helper: 'Para ${formatMonth(month)}. Escribe 0 para quitar el límite.',
      initialCents: line.limitCents,
      allowZero: hasLimit,
    );
    if (cents == null) return;
    await repo.setLimit(line.category.id, month, cents);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final limit = line.limitCents;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _edit(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CategoryAvatar(category: line.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(line.category.name, style: theme.textTheme.titleSmall)),
                          if (limit != null)
                            Text('${(line.ratio * 100).round()} %',
                                style: theme.textTheme.labelLarge?.copyWith(color: levelColor(context, line.level))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (limit != null) ...[
                        ProgressBar(value: line.ratio, color: levelColor(context, line.level)),
                        const SizedBox(height: 6),
                        Text('${formatMoney(line.spentCents)} de ${formatMoney(limit)}', style: theme.textTheme.bodySmall),
                      ] else
                        Text(
                          line.spentCents > 0 ? 'Gastado: ${formatMoney(line.spentCents)} · Toca para fijar límite' : 'Toca para fijar límite',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
