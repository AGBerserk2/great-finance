import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/category_icons.dart';
import '../../app/providers.dart';
import '../../data/database.dart';
import '../../widgets/common.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categorías'),
          bottom: const TabBar(tabs: [Tab(text: 'Gastos'), Tab(text: 'Ingresos')]),
        ),
        body: const TabBarView(children: [
          _CategoryList(kind: CategoryKind.expense),
          _CategoryList(kind: CategoryKind.income),
        ]),
        floatingActionButton: Builder(
          builder: (c) => FloatingActionButton(
            tooltip: 'Nueva categoría',
            onPressed: () => _showCategoryDialog(
              c,
              ref,
              kind: DefaultTabController.of(c).index == 0 ? CategoryKind.expense : CategoryKind.income,
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.kind});
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(categoriesProvider(kind)).valueOrNull ?? const [];
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final c in list)
          ListTile(
            leading: CategoryAvatar(category: c),
            title: Text(c.name),
            trailing: IconButton(
              tooltip: 'Archivar',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: '¿Archivar "${c.name}"?',
                    message: 'Ya no aparecerá para nuevos movimientos. Lo registrado se conserva.',
                    confirm: 'Archivar');
                if (ok) await ref.read(categoriesRepoProvider).setArchived(c.id, true);
              },
            ),
            onTap: () => _showCategoryDialog(context, ref, kind: kind, existing: c),
          ),
      ],
    );
  }
}

Future<void> _showCategoryDialog(BuildContext context, WidgetRef ref, {required CategoryKind kind, Category? existing}) {
  return showDialog(context: context, builder: (_) => _CategoryDialog(kind: kind, existing: existing));
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({required this.kind, this.existing});
  final CategoryKind kind;
  final Category? existing;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? categoryIcons.keys.first;
  late int _color = widget.existing?.color ?? categoryColors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(categoriesRepoProvider);
    final name = _name.text.trim();
    if (widget.existing == null) {
      await repo.add(name: name, icon: _icon, color: _color, kind: widget.kind);
    } else {
      await repo.edit(widget.existing!.id, name: name, icon: _icon, color: _color);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nueva categoría' : 'Editar categoría'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Ponle un nombre' : null,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in categoryColors)
                      GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(c),
                          child: _color == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final e in categoryIcons.entries)
                      IconButton(
                        isSelected: _icon == e.key,
                        style: IconButton.styleFrom(
                          backgroundColor: _icon == e.key ? Color(_color).withValues(alpha: 0.25) : null,
                        ),
                        icon: Icon(e.value, color: _icon == e.key ? Color(_color) : null),
                        onPressed: () => setState(() => _icon = e.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
