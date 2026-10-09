import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';
import '../goals_debts/goals_debts_screen.dart';
import '../payments/occurrence_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(DateTime.now());
    final month = monthStart(today);
    final totals = ref.watch(monthTotalsProvider(month)).valueOrNull;
    final occurrences = ref.watch(occurrencesProvider).valueOrNull ?? const [];
    final budget = ref.watch(budgetLinesProvider(month)).valueOrNull ?? const [];
    final goals = ref.watch(goalsProvider).valueOrNull ?? const [];
    final debts = ref.watch(debtsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    final soon = collapseDaily(occurrences.where((v) => v.payment.active).toList(), today)
        .where((v) => v.isOpen && (v.isOverdue(today) || !v.occurrence.dueDate.isAfter(addDays(today, 7))))
        .toList();
    final topBudget = (budget.where((l) => l.limitCents != null).toList()..sort((a, b) => b.ratio.compareTo(a.ratio)))
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(formatMonth(today)),
        actions: [
          IconButton(tooltip: 'Ajustes', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/ajustes')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          _BalanceCard(
            income: totals?.incomeCents ?? 0,
            outflow: totals?.outflowCents ?? 0,
            available: totals?.availableCents ?? 0,
          ),
          SectionHeader('Próximos pagos', action: TextButton(onPressed: () => context.go('/pagos'), child: const Text('Ver todos'))),
          if (soon.isEmpty)
            Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline, color: MoneyColors.ok(context)),
                title: const Text('Nada pendiente esta semana'),
              ),
            )
          else
            Card(child: Column(children: [for (final v in soon) OccurrenceTile(view: v)])),
          SectionHeader('Presupuesto', action: TextButton(onPressed: () => context.go('/presupuesto'), child: const Text('Ver todo'))),
          if (topBudget.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.pie_chart_outline),
                title: const Text('Fija límites por categoría'),
                onTap: () => context.go('/presupuesto'),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final l in topBudget)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 8,
                              children: [
                                Text(l.category.name),
                                Text('${formatMoney(l.spentCents)} / ${formatMoney(l.limitCents!)}', style: theme.textTheme.bodySmall),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ProgressBar(value: l.ratio, color: levelColor(context, l.level)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (goals.isNotEmpty || debts.isNotEmpty) ...[
            SectionHeader('Metas y deudas', action: TextButton(onPressed: () => context.go('/metas'), child: const Text('Ver todo'))),
            Card(
              child: Column(
                children: [
                  for (final g in goals)
                    ListTile(
                      leading: Icon(Icons.savings_outlined, color: MoneyColors.saving(context)),
                      title: Text(g.goal.name),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ProgressBar(value: g.ratio, color: MoneyColors.saving(context)),
                      ),
                      trailing: Text('${(g.ratio * 100).round()} %'),
                      onTap: () {
                        ref.read(goalsDebtsTabProvider.notifier).state = GoalsDebtsTab.goals;
                        context.go('/metas');
                      },
                    ),
                  for (final d in debts)
                    ListTile(
                      leading: Icon(Icons.credit_card, color: theme.colorScheme.primary),
                      title: Text(d.name),
                      subtitle: Text(debtProjectionText(d), maxLines: 2),
                      trailing: Text(formatMoney(d.balanceCents)),
                      onTap: () {
                        ref.read(goalsDebtsTabProvider.notifier).state = GoalsDebtsTab.debts;
                        context.go('/metas');
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.income, required this.outflow, required this.available});
  final int income;
  final int outflow;
  final int available;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Disponible este mes', style: text.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                formatMoney(available),
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, color: available < 0 ? scheme.error : scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Figure(icon: Icons.arrow_downward, label: 'Entró', cents: income)),
                Expanded(child: _Figure(icon: Icons.arrow_upward, label: 'Salió', cents: outflow)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.icon, required this.label, required this.cents});
  final IconData icon;
  final String label;
  final int cents;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
              FittedBox(child: Text(formatMoney(cents), style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ],
    );
  }
}
