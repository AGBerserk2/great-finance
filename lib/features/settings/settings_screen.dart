import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../services/backup_service.dart';
import '../../widgets/common.dart';
import '../payments/planned_payment_form.dart';
import 'categories_screen.dart';

final _defaultTimeProvider = FutureProvider<TimeOfDay>((ref) async {
  final db = ref.watch(databaseProvider);
  final h = int.tryParse(await db.getSetting(remindHourKey) ?? '') ?? 9;
  final m = int.tryParse(await db.getSetting(remindMinuteKey) ?? '') ?? 0;
  return TimeOfDay(hour: h, minute: m);
});

String _stamp(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}-${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final json = await ref.read(backupServiceProvider).exportJson();
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'ag-finanzas-${_stamp(DateTime.now())}.json'));
      await file.writeAsString(json);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')], subject: 'Respaldo AG Finanzas'));
    } catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo exportar: $e');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final service = ref.read(backupServiceProvider);
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final data = service.parse(utf8.decode(await files.single.readAsBytes()));
      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: '¿Reemplazar tus datos?',
        message: 'Todo lo que tienes ahora se reemplaza por el respaldo. Antes guardo una copia automática.',
        confirm: 'Importar',
      );
      if (!ok) return;

      final docs = await getApplicationDocumentsDirectory();
      final backups = Directory(p.join(docs.path, 'respaldos'))..createSync(recursive: true);
      await File(p.join(backups.path, 'auto-${_stamp(DateTime.now())}.json')).writeAsString(await service.exportJson());

      await service.importData(data);
      await ref.read(schedulerProvider).sync();
      if (context.mounted) showSnack(context, 'Respaldo importado');
    } on BackupFormatException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo importar: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(notificationsEnabledProvider).valueOrNull;
    final time = ref.watch(_defaultTimeProvider).valueOrNull ?? const TimeOfDay(hour: 9, minute: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _Header('Notificaciones'),
          ListTile(
            leading: Icon(enabled == false ? Icons.notifications_off : Icons.notifications_active),
            title: const Text('Permiso de notificaciones'),
            subtitle: Text(enabled == false ? 'Desactivadas — toca para activar' : 'Activadas'),
            onTap: () async {
              await ref.read(notificationServiceProvider).requestPermissions();
              ref.invalidate(notificationsEnabledProvider);
              await ref.read(schedulerProvider).sync();
            },
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Hora por defecto de recordatorios'),
            subtitle: Text('${formatTime(time.hour, time.minute)} · se usa al crear pagos nuevos'),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked == null) return;
              final db = ref.read(databaseProvider);
              await db.setSetting(remindHourKey, '${picked.hour}');
              await db.setSetting(remindMinuteKey, '${picked.minute}');
              ref.invalidate(_defaultTimeProvider);
            },
          ),
          const _Header('Datos'),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categorías'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Exportar respaldo'),
            subtitle: const Text('Guárdalo en Drive, WhatsApp o donde quieras'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Importar respaldo'),
            subtitle: const Text('Reemplaza los datos actuales'),
            onTap: () => _import(context, ref),
          ),
          const _Header('Acerca de'),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Tus datos se quedan en este teléfono'),
            subtitle: Text('Sin cuentas ni servidores. Haz respaldos de vez en cuando.'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
