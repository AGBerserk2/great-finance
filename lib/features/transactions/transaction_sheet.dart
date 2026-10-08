import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/category_icons.dart';
import '../../app/format.dart';
import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../widgets/common.dart';

/// Hoja para registrar o editar un gasto/ingreso. Los ahorros y pagos de deuda solo permiten
/// cambiar monto, fecha y nota (su tipo y vínculo no cambian).
Future<void> showTransactionSheet(BuildContext context, {Txn? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => TransactionSheet(existing: existing),
  );
}

class TransactionSheet extends ConsumerStatefulWidget {
  const TransactionSheet({super.key, this.existing});
  final Txn? existing;

  @override
  ConsumerState<TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends ConsumerState<TransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.existing == null ? '' : centsToInput(widget.existing!.amountCents));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late int? _categoryId = widget.existing?.categoryId;
  late DateTime _date = widget.existing?.date ?? dateOnly(DateTime.now());
  bool _categoryError = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _linked => widget.existing != null && (widget.existing!.kind == TxKind.saving || widget.existing!.debtId != null);

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final validForm = _formKey.currentState!.validate();
    final needsCategory = !_linked;
    setState(() => _categoryError = needsCategory && _categoryId == null);
    if (!validForm || _categoryError) return;

    setState(() => _saving = true);
    final ledger = ref.read(ledgerProvider);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final cents = parseMoneyToCents(_amount.text)!;
    try {
      if (_isEditing) {
        await ledger.edit(
          widget.existing!,
          TransactionsCompanion(
            amountCents: Value(cents),
            date: Value(_date),
            note: Value(note),
            kind: _linked ? const Value.absent() : Value(_kind),
            categoryId: _linked ? const Value.absent() : Value(_categoryId),
          ),
        );
      } else {
        await ledger.add(TransactionsCompanion.insert(
          kind: _kind,
          amountCents: cents,
          categoryId: Value(_categoryId),
          date: _date,
          note: Value(note),
        ));
      }
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
      title: '¿Borrar este movimiento?',
      message: widget.existing!.occurrenceId != null
          ? 'El pago planeado volverá a quedar pendiente.'
          : widget.existing!.debtId != null
              ? 'El monto se devolverá al saldo de la deuda.'
              : null,
      confirm: 'Borrar',
    );
    if (!ok) return;
    await ref.read(ledgerProvider).delete(widget.existing!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final categoryKind = _kind == TxKind.income ? CategoryKind.income : CategoryKind.expense;
    final categories = ref.watch(categoriesProvider(categoryKind)).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEditing ? 'Editar movimiento' : 'Nuevo movimiento', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              if (!_linked)
                SegmentedButton<TxKind>(
                  segments: const [
                    ButtonSegment(value: TxKind.expense, label: Text('Gasto'), icon: Icon(Icons.arrow_upward)),
                    ButtonSegment(value: TxKind.income, label: Text('Ingreso'), icon: Icon(Icons.arrow_downward)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _categoryId = null;
                  }),
                ),
              if (!_linked) const SizedBox(height: 16),
              MoneyField(controller: _amount, autofocus: !_isEditing, large: true),
              if (!_linked) ...[
                const SizedBox(height: 16),
                Text('Categoría', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in categories)
                      ChoiceChip(
                        avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                        label: Text(c.name),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() {
                          _categoryId = c.id;
                          _categoryError = false;
                        }),
                      ),
                  ],
                ),
                if (_categoryError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Elige una categoría', style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatDayHeader(_date, DateTime.now())),
                trailing: const Text('Cambiar'),
                onTap: _pickDate,
              ),
              TextFormField(
                controller: _note,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(_isEditing ? 'Guardar cambios' : 'Guardar'),
              ),
              if (_isEditing)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Borrar'),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
