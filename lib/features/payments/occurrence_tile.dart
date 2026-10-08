import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/database.dart';
import '../../data/repositories/payments_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';

/// Ejecuta una acción sobre una ocurrencia desde la app y reprograma recordatorios.
Future<void> runOccurrenceAction(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
  try {
    await action();
    await ref.read(schedulerProvider).sync();
    if (context.mounted) showSnack(context, done);
  } catch (e) {
    if (context.mounted) showSnack(context, 'No se pudo completar: $e');
  }
}

class OccurrenceTile extends ConsumerWidget {
  const OccurrenceTile({super.key, required this.view});
  final OccurrenceView view;

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final cents = await askAmount(
      context,
      title: 'Registrar pago',
      helper: view.payment.name,
      initialCents: view.payment.amountCents,
      confirm: 'Pagué',
    );
    if (cents == null || !context.mounted) return;
    await runOccurrenceAction(
      context,
      ref,
      () => ref.read(paymentActionsProvider).markPaid(view.occurrence.id, amountCents: cents),
      '${view.payment.name}: registrado',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final o = view.occurrence;
    final today = dateOnly(DateTime.now());
    final overdue = view.isOverdue(today);
    final (statusText, statusColor) = switch (o.status) {
      OccurrenceStatus.paid => ('Pagado', MoneyColors.ok(context)),
      OccurrenceStatus.skipped => ('No se pagó', theme.colorScheme.onSurfaceVariant),
      OccurrenceStatus.snoozed when overdue => ('Atrasado', MoneyColors.danger(context)),
      OccurrenceStatus.snoozed => ('Pospuesto al ${formatShortDate(o.snoozedUntil!)}', MoneyColors.warning(context)),
      OccurrenceStatus.pending when overdue => ('Atrasado', MoneyColors.danger(context)),
      OccurrenceStatus.pending when o.dueDate == today => ('Vence hoy', MoneyColors.warning(context)),
      OccurrenceStatus.pending => ('Pendiente', theme.colorScheme.onSurfaceVariant),
    };
    final actions = ref.read(paymentActionsProvider);

    return ListTile(
      leading: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${o.dueDate.day}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: statusColor)),
            Text(formatShortDate(o.dueDate).split(' ').last, style: theme.textTheme.labelSmall?.copyWith(color: statusColor)),
          ],
        ),
      ),
      title: Text(view.payment.name),
      subtitle: Text('${formatMoney(view.payment.amountCents)} · $statusText', style: TextStyle(color: statusColor)),
      trailing: view.isOpen
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonal(onPressed: () => _pay(context, ref), child: const Text('Pagué')),
                PopupMenuButton<String>(
                  tooltip: 'Más opciones',
                  onSelected: (v) => switch (v) {
                    'snooze1' => runOccurrenceAction(context, ref, () => actions.snooze(o.id, 1), 'Te recuerdo mañana'),
                    'snooze3' => runOccurrenceAction(context, ref, () => actions.snooze(o.id, 3), 'Te recuerdo en 3 días'),
                    _ => runOccurrenceAction(context, ref, () => actions.skip(o.id), 'Marcado como no pagado'),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'snooze1', child: Text('Recordar mañana')),
                    PopupMenuItem(value: 'snooze3', child: Text('Recordar en 3 días')),
                    PopupMenuItem(value: 'skip', child: Text('No lo pagaré')),
                  ],
                ),
              ],
            )
          : null,
    );
  }
}
