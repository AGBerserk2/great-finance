import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';

Future<void> showGoalForm(BuildContext context, {Goal? existing}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GoalForm(existing: existing),
    );

Future<void> showDebtForm(BuildContext context, {Debt? existing}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DebtForm(existing: existing),
    );

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({this.existing});
  final Goal? existing;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _target =
      TextEditingController(text: widget.existing == null ? '' : centsToInput(widget.existing!.targetCents));
  late DateTime? _deadline = widget.existing?.deadline;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(goalsRepoProvider);
    final name = _name.text.trim();
    final target = parseMoneyToCents(_target.text)!;
    if (widget.existing == null) {
      await repo.add(GoalsCompanion.insert(name: name, targetCents: target, deadline: Value(_deadline)));
    } else {
      await repo.edit(widget.existing!.id,
          GoalsCompanion(name: Value(name), targetCents: Value(target), deadline: Value(_deadline)));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      formKey: _formKey,
      title: widget.existing == null ? 'Nueva meta de ahorro' : 'Editar meta',
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Fondo de emergencia, Viaje'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Ponle un nombre' : null,
        ),
        const SizedBox(height: 16),
        MoneyField(controller: _target, label: 'Monto objetivo'),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Fecha límite (opcional)'),
          subtitle: Text(_deadline == null ? 'Sin fecha' : formatLongDate(_deadline!)),
          trailing: _deadline == null
              ? null
              : IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close), onPressed: () => setState(() => _deadline = null)),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _deadline ?? addMonths(dateOnly(now), 6),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _deadline = dateOnly(picked));
          },
        ),
      ],
    );
  }
}

class _DebtForm extends ConsumerStatefulWidget {
  const _DebtForm({this.existing});
  final Debt? existing;

  @override
  ConsumerState<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends ConsumerState<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _balance =
      TextEditingController(text: widget.existing == null ? '' : centsToInput(widget.existing!.balanceCents));
  late final _rate = TextEditingController(
      text: widget.existing == null ? '' : widget.existing!.annualRatePct.toString().replaceAll(RegExp(r'\.0$'), ''));
  late final _payment =
      TextEditingController(text: widget.existing == null ? '' : centsToInput(widget.existing!.monthlyPaymentCents));

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _rate.dispose();
    _payment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(debtsRepoProvider);
    final name = _name.text.trim();
    final balance = parseMoneyToCents(_balance.text)!;
    final rate = double.parse(_rate.text.replaceAll(',', '.'));
    final payment = parseMoneyToCents(_payment.text)!;
    final existing = widget.existing;
    if (existing == null) {
      await repo.add(DebtsCompanion.insert(
        name: name,
        originalCents: balance,
        balanceCents: balance,
        annualRatePct: rate,
        monthlyPaymentCents: payment,
      ));
    } else {
      await repo.edit(
        existing.id,
        DebtsCompanion(
          name: Value(name),
          balanceCents: Value(balance),
          // Si el saldo sube por encima del original, el original se ajusta para que el progreso tenga sentido.
          originalCents: Value(balance > existing.originalCents ? balance : existing.originalCents),
          annualRatePct: Value(rate),
          monthlyPaymentCents: Value(payment),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      formKey: _formKey,
      title: widget.existing == null ? 'Nueva deuda' : 'Editar deuda',
      onSave: _save,
      children: [
        TextFormField(
          controller: _name,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Tarjeta, Préstamo del carro'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Ponle un nombre' : null,
        ),
        const SizedBox(height: 16),
        MoneyField(controller: _balance, label: widget.existing == null ? 'Lo que debes hoy' : 'Saldo actual'),
        const SizedBox(height: 16),
        TextFormField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Tasa de interés anual', suffixText: '%', helperText: 'Pon 0 si no cobra interés'),
          validator: (v) {
            final r = double.tryParse((v ?? '').replaceAll(',', '.'));
            if (r == null || r < 0 || r > 200) return 'Escribe una tasa entre 0 y 200';
            return null;
          },
        ),
        const SizedBox(height: 16),
        MoneyField(controller: _payment, label: 'Cuota mensual'),
      ],
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.formKey, required this.title, required this.onSave, required this.children});
  final GlobalKey<FormState> formKey;
  final String title;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...children,
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
