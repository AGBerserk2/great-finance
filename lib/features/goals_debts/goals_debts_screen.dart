import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/database.dart';
import '../../data/repositories/goals_repository.dart';
import '../../domain/dates.dart';
import '../../domain/debt_projection.dart';
import '../../domain/goal_pace.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';
import 'goal_debt_forms.dart';

enum GoalsDebtsTab { goals, debts }

final goalsDebtsTabProvider = StateProvider((ref) => GoalsDebtsTab.goals);

class GoalsDebtsScreen extends ConsumerWidget {
  const GoalsDebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(goalsDebtsTabProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Metas y deudas')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-goal-debt',
        onPressed: () => tab == GoalsDebtsTab.goals ? showGoalForm(context) : showDebtForm(context),
        icon: const Icon(Icons.add),
        label: Text(tab == GoalsDebtsTab.goals ? 'Nueva meta' : 'Nueva deuda'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<GoalsDebtsTab>(
                segments: const [
                  ButtonSegment(value: GoalsDebtsTab.goals, label: Text('Metas'), icon: Icon(Icons.savings_outlined)),
                  ButtonSegment(value: GoalsDebtsTab.debts, label: Text('Deudas'), icon: Icon(Icons.credit_card)),
                ],
                selected: {tab},
                onSelectionChanged: (s) => ref.read(goalsDebtsTabProvider.notifier).state = s.first,
              ),
            ),
          ),
          Expanded(child: tab == GoalsDebtsTab.goals ? const _GoalsList() : const _DebtsList()),
        ],
      ),
    );
  }
}

class _GoalsList extends ConsumerWidget {
  const _GoalsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(goalsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (goals) => goals.isEmpty
              ? const EmptyState(icon: Icons.savings_outlined, message: 'Crea una meta y ve abonándole poco a poco.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: goals.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => GoalCard(progress: goals[i]),
                ),
        );
  }
}

class GoalCard extends ConsumerWidget {
  const GoalCard({super.key, required this.progress});
  final GoalProgress progress;

  Future<void> _contribute(BuildContext context, WidgetRef ref) async {
    final g = progress.goal;
    final cents = await askAmount(context, title: 'Abonar a ${g.name}', confirm: 'Abonar');
    if (cents == null) return;
    await ref.read(ledgerProvider).add(TransactionsCompanion.insert(
          kind: TxKind.saving,
          amountCents: cents,
          goalId: Value(g.id),
          date: dateOnly(DateTime.now()),
        ));
    if (context.mounted) showSnack(context, 'Abonaste ${formatMoney(cents)} a ${g.name}');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'edit':
        await showGoalForm(context, existing: progress.goal);
      case 'archive':
        final ok = await confirmDialog(context,
            title: '¿Archivar "${progress.goal.name}"?',
            message: 'Deja de aparecer aquí. Los abonos se quedan en tus movimientos.',
            confirm: 'Archivar');
        if (ok) await ref.read(goalsRepoProvider).archive(progress.goal.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final g = progress.goal;
    final needed = monthlyNeeded(
      targetCents: g.targetCents,
      savedCents: progress.savedCents,
      deadline: g.deadline,
      today: DateTime.now(),
    );
    final color = progress.done ? MoneyColors.ok(context) : MoneyColors.saving(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(g.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                PopupMenuButton<String>(
                  onSelected: (a) => _menu(context, ref, a),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'archive', child: Text('Archivar')),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: formatMoney(progress.savedCents), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                    TextSpan(text: '  de ${formatMoney(g.targetCents)}', style: theme.textTheme.bodyMedium),
                  ])),
                  const SizedBox(height: 10),
                  ProgressBar(value: progress.ratio, color: color, height: 10),
                  const SizedBox(height: 8),
                  Text(
                    progress.done
                        ? '¡Meta cumplida! 🎉'
                        : [
                            '${(progress.ratio * 100).round()} %',
                            if (g.deadline != null) 'para ${formatShortDate(g.deadline!)} ${g.deadline!.year}',
                            if (needed != null) 'ahorra ${formatMoney(needed)}/mes',
                          ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (!progress.done)
                    FilledButton.tonalIcon(
                      onPressed: () => _contribute(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Abonar'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtsList extends ConsumerWidget {
  const _DebtsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(debtsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (debts) {
            if (debts.isEmpty) {
              return const EmptyState(icon: Icons.credit_card, message: 'Agrega tus deudas para ver cuándo terminas de pagarlas.');
            }
            final total = debts.fold<int>(0, (s, d) => s + d.balanceCents);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text('Debes en total ${formatMoney(total)}', style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final d in debts) Padding(padding: const EdgeInsets.only(bottom: 12), child: DebtCard(debt: d)),
              ],
            );
          },
        );
  }
}

String debtProjectionText(Debt d) {
  final p = projectDebt(
    balanceCents: d.balanceCents,
    annualRatePct: d.annualRatePct,
    monthlyPaymentCents: d.monthlyPaymentCents,
    today: DateTime.now(),
  );
  return switch (p.status) {
    DebtStatus.paid => '¡Pagada! 🎉',
    DebtStatus.paymentTooLow => 'La cuota no cubre el interés: la deuda no baja.',
    DebtStatus.tooLong => 'Con esta cuota tardarías más de 50 años.',
    DebtStatus.ok => 'Terminas en ${formatMonthShort(p.payoffDate!)} (${p.months} ${p.months == 1 ? 'mes' : 'meses'})'
        '${p.totalInterestCents > 0 ? ' · interés restante ${formatMoney(p.totalInterestCents)}' : ''}',
  };
}

class DebtCard extends ConsumerWidget {
  const DebtCard({super.key, required this.debt});
  final Debt debt;

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final cents = await askAmount(context, title: 'Abonar a ${debt.name}', initialCents: debt.monthlyPaymentCents, confirm: 'Abonar');
    if (cents == null) return;
    final category = await ref.read(categoriesRepoProvider).byName('Deudas');
    await ref.read(ledgerProvider).add(TransactionsCompanion.insert(
          kind: TxKind.expense,
          amountCents: cents,
          categoryId: Value(category?.id),
          debtId: Value(debt.id),
          note: Value(debt.name),
          date: dateOnly(DateTime.now()),
        ));
    if (context.mounted) showSnack(context, 'Abonaste ${formatMoney(cents)} a ${debt.name}');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'adjust':
        final cents = await askAmount(
          context,
          title: 'Ajustar saldo',
          helper: 'Pon el saldo que dice tu estado de cuenta. No crea un movimiento.',
          initialCents: debt.balanceCents,
          allowZero: true,
        );
        if (cents != null) await ref.read(debtsRepoProvider).adjustBalance(debt.id, cents);
      case 'edit':
        await showDebtForm(context, existing: debt);
      case 'archive':
        final ok = await confirmDialog(context,
            title: '¿Archivar "${debt.name}"?',
            message: 'Deja de aparecer aquí. Los pagos se quedan en tus movimientos.',
            confirm: 'Archivar');
        if (ok) await ref.read(debtsRepoProvider).archive(debt.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paid = debt.originalCents - debt.balanceCents;
    final ratio = debt.originalCents <= 0 ? 1.0 : paid / debt.originalCents;
    final paidOff = debt.balanceCents <= 0;
    final color = paidOff ? MoneyColors.ok(context) : theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(debt.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                PopupMenuButton<String>(
                  onSelected: (a) => _menu(context, ref, a),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'adjust', child: Text('Ajustar saldo')),
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'archive', child: Text('Archivar')),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Te falta', style: theme.textTheme.labelMedium),
                  Text(formatMoney(debt.balanceCents), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ProgressBar(value: ratio, color: color, height: 10),
                  const SizedBox(height: 6),
                  Text('Pagado ${formatMoney(paid)} de ${formatMoney(debt.originalCents)} · ${(ratio * 100).round()} %',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '${debt.annualRatePct.toString().replaceAll(RegExp(r'\.0$'), '')} % anual · cuota ${formatMoney(debt.monthlyPaymentCents)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(debtProjectionText(debt), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                  if (!paidOff) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(onPressed: () => _pay(context, ref), icon: const Icon(Icons.payments_outlined), label: const Text('Abonar')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
