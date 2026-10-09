import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/category_icons.dart';
import '../../app/format.dart';
import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/recurrence.dart';
import '../../widgets/common.dart';

const remindHourKey = 'remind_hour';
const remindMinuteKey = 'remind_minute';

enum _Link { none, debt, goal }

class PlannedPaymentForm extends ConsumerStatefulWidget {
  const PlannedPaymentForm({super.key, this.existing});
  final PlannedPayment? existing;

  static Future<void> open(BuildContext context, {PlannedPayment? existing}) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlannedPaymentForm(existing: existing)));

  @override
  ConsumerState<PlannedPaymentForm> createState() => _PlannedPaymentFormState();
}

class _PlannedPaymentFormState extends ConsumerState<PlannedPaymentForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : centsToInput(widget.existing!.amountCents),
  );
  late Frequency _frequency = widget.existing?.frequency ?? Frequency.monthly;
  late DateTime _anchor = widget.existing?.anchorDate ?? dateOnly(DateTime.now());
  late TimeOfDay _time = TimeOfDay(hour: widget.existing?.remindHour ?? 9, minute: widget.existing?.remindMinute ?? 0);
  late int _daysBefore = widget.existing?.remindDaysBefore ?? 1;
  late int _weekdays = widget.existing?.weekdays ?? weekdaysAll;
  bool _weekdaysError = false;
  late int? _categoryId = widget.existing?.categoryId;
  late int? _debtId = widget.existing?.debtId;
  late int? _goalId = widget.existing?.goalId;
  late _Link _link = _debtId != null ? _Link.debt : (_goalId != null ? _Link.goal : _Link.none);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing == null) _loadDefaultTime();
  }

  Future<void> _loadDefaultTime() async {
    final db = ref.read(databaseProvider);
    final h = int.tryParse(await db.getSetting(remindHourKey) ?? '');
    final m = int.tryParse(await db.getSetting(remindMinuteKey) ?? '');
    if (h != null && mounted) setState(() => _time = TimeOfDay(hour: h, minute: m ?? 0));
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _isDaily => _frequency == Frequency.daily;

  Future<void> _save() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _weekdaysError = _isDaily && _weekdays == 0);
    if (!valid || _weekdaysError) return;
    setState(() => _saving = true);
    final companion = PlannedPaymentsCompanion(
      name: Value(_name.text.trim()),
      amountCents: Value(parseMoneyToCents(_amount.text)!),
      categoryId: Value(_link == _Link.goal ? null : _categoryId),
      frequency: Value(_frequency),
      anchorDate: Value(_anchor),
      remindHour: Value(_time.hour),
      remindMinute: Value(_time.minute),
      remindDaysBefore: Value(_isDaily ? 0 : _daysBefore),
      weekdays: Value(_isDaily ? _weekdays : weekdaysAll),
      debtId: Value(_link == _Link.debt ? _debtId : null),
      goalId: Value(_link == _Link.goal ? _goalId : null),
    );
    final repo = ref.read(paymentsRepoProvider);
    try {
      if (widget.existing == null) {
        await repo.addPlanned(companion);
      } else {
        await repo.updatePlanned(widget.existing!.id, companion, DateTime.now());
      }
      await ref.read(schedulerProvider).sync();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'No se pudo guardar: $e');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: '¿Eliminar "${widget.existing!.name}"?',
      message: 'Ya no te llegarán recordatorios. Lo que ya pagaste se queda en tus movimientos.',
      confirm: 'Eliminar',
    );
    if (!ok) return;
    await ref.read(paymentsRepoProvider).deactivate(widget.existing!.id, DateTime.now());
    await ref.read(schedulerProvider).sync();
    if (mounted) Navigator.pop(context);
  }

  String get _anchorLabel => switch (_frequency) {
    Frequency.once => 'Fecha del pago',
    Frequency.daily || Frequency.biweekly => 'A partir de',
    _ => 'Primer vencimiento',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider(CategoryKind.expense)).valueOrNull ?? const [];
    final debts = ref.watch(debtsProvider).valueOrNull ?? const [];
    final goals = ref.watch(activeGoalsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nuevo pago planeado' : 'Editar pago'),
        actions: [
          if (widget.existing != null)
            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Luz, Internet, Préstamo'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Ponle un nombre' : null,
            ),
            const SizedBox(height: 16),
            MoneyField(controller: _amount),
            const SizedBox(height: 20),
            Text('¿Cada cuánto?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (f, label) in const [
                  (Frequency.once, 'Una vez'),
                  (Frequency.daily, 'Diario'),
                  (Frequency.weekly, 'Semanal'),
                  (Frequency.biweekly, 'Quincenal'),
                  (Frequency.monthly, 'Mensual'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _frequency == f,
                    onSelected: (_) => setState(() => _frequency = f),
                  ),
              ],
            ),
            if (_isDaily) ...[
              const SizedBox(height: 12),
              Text('¿Qué días?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _WeekdayPicker(
                value: _weekdays,
                onChanged: (v) => setState(() {
                  _weekdays = v;
                  _weekdaysError = false;
                }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _weekdaysError
                      ? 'Marca al menos un día'
                      : 'Te pregunto esos días a la hora del recordatorio. Si no lo gastaste, no se registra.',
                  style: theme.textTheme.bodySmall?.copyWith(color: _weekdaysError ? theme.colorScheme.error : null),
                ),
              ),
            ],
            if (_frequency == Frequency.biweekly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Los días 15 y último de cada mes.', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_anchorLabel),
              subtitle: Text(formatLongDate(_anchor)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _anchor,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _anchor = dateOnly(picked));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Hora del recordatorio'),
              subtitle: Text(formatTime(_time.hour, _time.minute)),
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
            ),
            if (!_isDaily)
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _daysBefore,
                decoration: const InputDecoration(labelText: 'Avisarme'),
                items: [
                  for (final d in const [0, 1, 2, 3, 5, 7])
                    DropdownMenuItem(
                      value: d,
                      child: Text(
                        d == 0
                            ? 'El mismo día'
                            : d == 1
                            ? '1 día antes'
                            : '$d días antes',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _daysBefore = v!),
              ),
            const SizedBox(height: 20),
            Text('¿Va ligado a algo?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<_Link>(
              segments: const [
                ButtonSegment(value: _Link.none, label: Text('Nada')),
                ButtonSegment(value: _Link.debt, label: Text('Deuda')),
                ButtonSegment(value: _Link.goal, label: Text('Meta')),
              ],
              selected: {_link},
              onSelectionChanged: (s) => setState(() {
                _link = s.first;
                if (_link == _Link.debt && _categoryId == null) {
                  _categoryId = categories.where((c) => c.name == 'Deudas').firstOrNull?.id;
                }
              }),
            ),
            const SizedBox(height: 12),
            if (_link == _Link.debt)
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: debts.any((d) => d.id == _debtId) ? _debtId : null,
                decoration: const InputDecoration(labelText: 'Deuda'),
                items: [for (final d in debts) DropdownMenuItem(value: d.id, child: Text(d.name))],
                onChanged: (v) => setState(() => _debtId = v),
                validator: (v) =>
                    v == null ? (debts.isEmpty ? 'Primero crea una deuda en Metas y Deudas' : 'Elige la deuda') : null,
              ),
            if (_link == _Link.goal)
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: goals.any((g) => g.id == _goalId) ? _goalId : null,
                decoration: const InputDecoration(labelText: 'Meta'),
                items: [for (final g in goals) DropdownMenuItem(value: g.id, child: Text(g.name))],
                onChanged: (v) => setState(() => _goalId = v),
                validator: (v) =>
                    v == null ? (goals.isEmpty ? 'Primero crea una meta en Metas y Deudas' : 'Elige la meta') : null,
              ),
            if (_link != _Link.goal) ...[
              if (_link == _Link.debt) const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Elige una categoría' : null,
              ),
            ],
            if (_link == _Link.goal)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Al pagarlo se registra como ahorro para la meta (no cuenta en el presupuesto).',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  static const _letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _names = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Semantics(
                      label: _names[i],
                      selected: value & (1 << i) != 0,
                      button: true,
                      child: Material(
                        shape: const CircleBorder(),
                        color: value & (1 << i) != 0 ? scheme.primary : scheme.surfaceContainerHighest,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => onChanged(value ^ (1 << i)),
                          child: Center(
                            child: MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.3,
                              child: Text(
                                _letters[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: value & (1 << i) != 0 ? scheme.onPrimary : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(label: const Text('Lunes a viernes'), onPressed: () => onChanged(weekdaysMonToFri)),
            ActionChip(label: const Text('Todos'), onPressed: () => onChanged(weekdaysAll)),
          ],
        ),
      ],
    );
  }
}
