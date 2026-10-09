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

/// Para listas: de cada gasto diario solo muestra la próxima ocurrencia abierta (hoy o la
/// siguiente) y descarta los días pasados sin contestar. Los demás pagos se dejan igual.
List<OccurrenceView> collapseDaily(List<OccurrenceView> views, DateTime today) {
  final t = dateOnly(today);
  final shownDaily = <int>{};
  return [
    for (final v in views)
      if (!v.isDaily)
        v
      else if (v.isOpen && (v.isOverdue(t) || !v.occurrence.dueDate.isBefore(t)) && shownDaily.add(v.payment.id))
        v,
  ];
}

class OccurrenceTile extends ConsumerWidget {
  const OccurrenceTile({super.key, required this.view});
  final OccurrenceView view;

  /// Ancho mínimo (en dp a escala 1) que necesita el texto para que los botones quepan al lado.
  static const _minInlineTextWidth = 150.0;
  static const _actionsWidth = 150.0;

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
      OccurrenceStatus.pending when o.dueDate == today => (view.isDaily ? 'Hoy' : 'Vence hoy', MoneyColors.warning(context)),
      OccurrenceStatus.pending => ('Pendiente', theme.colorScheme.onSurfaceVariant),
    };
    final actions = ref.read(paymentActionsProvider);

    final badge = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${o.dueDate.day}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: statusColor, height: 1.1)),
            Text(formatShortDate(o.dueDate).split(' ').last, style: theme.textTheme.labelSmall?.copyWith(color: statusColor)),
          ],
        ),
      ),
    );

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(view.payment.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(formatMoney(view.payment.amountCents),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(statusText, style: theme.textTheme.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );

    final buttons = view.isOpen
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
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'snooze1', child: Text('Recordar mañana')),
                  if (!view.isDaily) const PopupMenuItem(value: 'snooze3', child: Text('Recordar en 3 días')),
                  PopupMenuItem(value: 'skip', child: Text(view.isDaily ? 'Hoy no lo gasté' : 'No lo pagaré')),
                ],
              ),
            ],
          )
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final textWidth = constraints.maxWidth - 32 - 52 - 12 - (buttons == null ? 0 : _actionsWidth * scale);
      final inline = buttons == null || textWidth >= _minInlineTextWidth * scale;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                badge,
                const SizedBox(width: 12),
                Expanded(child: texts),
                if (inline && buttons != null) buttons,
              ],
            ),
            if (!inline) Padding(padding: const EdgeInsets.only(top: 4), child: buttons),
          ],
        ),
      );
    });
  }
}
