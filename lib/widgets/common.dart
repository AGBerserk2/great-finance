import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/category_icons.dart';
import '../app/format.dart';
import '../data/database.dart';
import '../domain/budget_status.dart';
import '../domain/money.dart';
import '../app/theme.dart';

/// Campo de monto en RD$ que valida un valor mayor que cero.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'Monto',
    this.autofocus = false,
    this.allowZero = false,
    this.large = false,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool allowZero;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = large ? Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600) : null;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      style: style,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, prefixText: 'RD\$ ', prefixStyle: style),
      validator: (v) {
        final cents = parseMoneyToCents(v ?? '');
        if (cents == null) return 'Escribe un monto válido';
        if (!allowZero && cents <= 0) return 'El monto debe ser mayor que 0';
        return null;
      },
    );
  }
}

class MonthSelector extends StatelessWidget {
  const MonthSelector({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Mes anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        SizedBox(
          width: 160,
          child: Text(formatMonth(month), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: 'Mes siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

Color levelColor(BuildContext context, BudgetLevel level) => switch (level) {
      BudgetLevel.ok => MoneyColors.ok(context),
      BudgetLevel.warning => MoneyColors.warning(context),
      BudgetLevel.over => MoneyColors.danger(context),
    };

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, required this.color, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height,
        color: color,
        backgroundColor: color.withValues(alpha: 0.15),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          ?action,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, this.category, this.fallbackIcon = Icons.savings, this.size = 40});
  final Category? category;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = category != null ? Color(category!.color) : MoneyColors.saving(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(size / 3)),
      child: Icon(category != null ? iconFor(category!.icon) : fallbackIcon, color: color, size: size * 0.55),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String confirm = 'Sí'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(confirm)),
      ],
    ),
  );
  return result ?? false;
}

/// Pide un monto. Devuelve centavos o `null` si se cancela.
Future<int?> askAmount(
  BuildContext context, {
  required String title,
  int? initialCents,
  String confirm = 'Guardar',
  bool allowZero = false,
  String? helper,
}) {
  final controller = TextEditingController(text: initialCents == null ? '' : centsToInput(initialCents));
  final formKey = GlobalKey<FormState>();
  return showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (helper != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(helper)),
            MoneyField(controller: controller, autofocus: true, allowZero: allowZero),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(c, parseMoneyToCents(controller.text));
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
