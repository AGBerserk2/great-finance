# AG Finanzas

App Android personal para llevar gastos, ingresos, presupuesto mensual, pagos planeados con
recordatorios que se responden desde la notificación (Pagué / No pagué), metas de ahorro y deudas.
Todo se guarda en el teléfono (SQLite); se puede exportar/importar un respaldo JSON desde Ajustes.

Diseño: `docs/superpowers/specs/2026-10-08-ag-finances-design.md`.

## Desarrollo

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # tras cambiar tablas de Drift
flutter analyze
flutter test
flutter run
```

## Instalar en el teléfono

```bash
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

O copia ese `.apk` al teléfono y ábrelo (permite "instalar apps desconocidas").
Al abrir la app por primera vez acepta las notificaciones y "Alarmas y recordatorios".
