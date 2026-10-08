import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'theme.dart';

const _askedPermissionsKey = 'asked_permissions';

class FinanzasApp extends ConsumerStatefulWidget {
  const FinanzasApp({super.key, required this.router});
  final GoRouter router;

  @override
  ConsumerState<FinanzasApp> createState() => _FinanzasAppState();
}

class _FinanzasAppState extends ConsumerState<FinanzasApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstLaunch());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Al volver a la app: refresca datos (el handler de notificaciones pudo escribir en otra
  /// conexión), revisa permisos y reprograma.
  Future<void> _onResume() async {
    _refresh();
    await _sync();
    // La acción de una notificación corre en otro engine y puede terminar un poco después.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    ref.read(databaseProvider).refreshAll();
    ref.invalidate(notificationsEnabledProvider);
    ref.invalidate(occurrencesProvider);
  }

  Future<void> _firstLaunch() async {
    final db = ref.read(databaseProvider);
    if (await db.getSetting(_askedPermissionsKey) == null) {
      await ref.read(notificationServiceProvider).requestPermissions();
      await db.setSetting(_askedPermissionsKey, '1');
      ref.invalidate(notificationsEnabledProvider);
    }
    await _sync();
  }

  Future<void> _sync() async {
    try {
      await ref.read(schedulerProvider).sync();
    } catch (e, s) {
      debugPrint('Error al programar recordatorios: $e\n$s');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AG Finanzas',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: widget.router,
    );
  }
}
