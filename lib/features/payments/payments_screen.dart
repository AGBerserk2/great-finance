import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/payments_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/recurrence.dart';
import '../../widgets/common.dart';
import 'occurrence_tile.dart';
import 'planned_payment_form.dart';

String frequencyLabel(PlannedPayment p) => switch (p.frequency) {
      Frequency.once => 'Una vez · ${formatShortDate(p.anchorDate)}',
      Frequency.daily => 'Diario · ${weekdaysLabel(p.weekdays)}',
      Frequency.weekly => 'Semanal',
      Frequency.biweekly => 'Quincenal (15 y fin de mes)',
      Frequency.monthly => 'Mensual · día ${p.anchorDate.day}',
    };

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occurrences = ref.watch(occurrencesProvider);
    final planned = ref.watch(plannedPaymentsProvider).valueOrNull ?? const [];
    final enabled = ref.watch(notificationsEnabledProvider).valueOrNull ?? true;
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Pagos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-payment',
        onPressed: () => PlannedPaymentForm.open(context),
        icon: const Icon(Icons.add_alert),
        label: const Text('Nuevo pago'),
      ),
      body: occurrences.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final active = collapseDaily(list.where((v) => v.payment.active).toList(), today);
          final overdue = active.where((v) => v.isOverdue(today)).toList();
          final upcoming = active
              .where((v) => v.isOpen && !v.isOverdue(today) && !v.occurrence.dueDate.isAfter(addDays(today, 30)))
              .toList();
          // De los gastos diarios solo interesa en el historial lo que sí se pagó.
          final history = list
              .where((v) =>
                  !v.isOpen &&
                  !v.occurrence.dueDate.isBefore(addDays(today, -30)) &&
                  (!v.isDaily || v.occurrence.status == OccurrenceStatus.paid))
              .toList()
            ..sort((a, b) => b.occurrence.dueDate.compareTo(a.occurrence.dueDate));

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (!enabled) const _PermissionBanner(),
              if (planned.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_none,
                  message: 'Agrega tus pagos fijos (luz, internet, préstamos…) o gastos diarios (transporte, almuerzo) y te aviso.',
                ),
              if (overdue.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SectionHeader('Atrasados')),
                for (final v in overdue) OccurrenceTile(view: v),
              ],
              if (upcoming.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SectionHeader('Próximos 30 días')),
                for (final v in upcoming) OccurrenceTile(view: v),
              ],
              if (planned.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SectionHeader('Mis pagos planeados')),
                for (final p in planned)
                  ListTile(
                    leading: Icon(p.frequency == Frequency.daily ? Icons.today : Icons.repeat),
                    title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${formatMoney(p.amountCents)} · ${frequencyLabel(p)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => PlannedPaymentForm.open(context, existing: p),
                  ),
              ],
              if (history.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SectionHeader('Últimos 30 días')),
                for (final OccurrenceView v in history) OccurrenceTile(view: v),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.notifications_off, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Las notificaciones están desactivadas. No te llegarán los recordatorios.',
                    style: TextStyle(color: scheme.onErrorContainer)),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(notificationServiceProvider).requestPermissions();
                  ref.invalidate(notificationsEnabledProvider);
                  await ref.read(schedulerProvider).sync();
                },
                child: const Text('Activar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
