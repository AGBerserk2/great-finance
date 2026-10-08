# AG Finanzas — Diseño

Fecha: 2026-10-08
Estado: aprobado

## 1. Objetivo

App nativa Android, de uso personal (un solo usuario), para llevar las finanzas propias:
registrar gastos e ingresos, presupuestar por categoría, planear pagos con recordatorios
que se responden **desde la notificación** ("Pagué" / "No pagué"), metas de ahorro y
seguimiento de deudas con interés.

**Criterios de éxito**
- Registrar un gasto toma segundos (botón "+" → monto, categoría, nota opcional).
- Los recordatorios llegan a tiempo y "Pagué" registra todo sin abrir la app.
- De un vistazo se ve: balance del mes, presupuestos, próximos pagos, metas y deudas.
- Los datos nunca se corrompen ni se duplican (montos exactos, operaciones atómicas).

**Decisiones del usuario**
- Datos **solo en el teléfono** (sin cuenta, sin servidor), con respaldo exportable a archivo.
- "Pagué" = todo automático (gasto + presupuesto + deuda/meta ligada).
- "No pagué" = elegir: Mañana / En 3 días / No lo pagaré.
- Deudas con tasa de interés, cuota y fecha estimada de pago.
- Ingresos sí; cuentas bancarias separadas no.

**Supuestos**
- Moneda única: peso dominicano (RD$). Idioma: español. Zona horaria del teléfono.
- Presupuesto mensual por categoría.
- "Notificaciones push" = notificaciones locales programadas (no requieren servidor).

**Fuera de alcance (v1):** sincronización/nube, múltiples cuentas, múltiples monedas,
deudas por cobrar, gráficas avanzadas, iOS, publicación en Play Store.

## 2. Stack

- Flutter 3.41 (Dart), solo Android.
- **Drift** (SQLite tipado, migraciones, consultas reactivas) + `drift_flutter`.
- **Riverpod** para estado e inyección de dependencias.
- **go_router** para navegación.
- **flutter_local_notifications** + `timezone` + `flutter_timezone` para recordatorios con acciones.
- `intl` (formato RD$ y fechas en español), `share_plus` (exportar), `file_picker` (importar),
  `path_provider`.

Nombre visible: "AG Finanzas". Package id: `com.zhonyas.agfinances`.

## 3. Pantallas

Navegación inferior con 5 pestañas, botón flotante "+" (registro rápido) e ícono de Ajustes arriba.

1. **Inicio** — balance del mes (ingresos, salidas, disponible); pagos de los próximos 7 días
   con estado; las 3 categorías de presupuesto con mayor % consumido; resumen de metas y deudas.
2. **Movimientos** — lista del mes agrupada por día; selector de mes; filtro por tipo/categoría;
   editar y borrar.
3. **Presupuesto** — por mes: cada categoría de gasto con límite, gastado y barra
   (verde < 80 %, amarillo 80–99 %, rojo ≥ 100 %). Si el mes no tiene límites, se copian los del mes anterior al abrirlo.
4. **Pagos** — lista de pagos planeados y de sus próximas ocurrencias con estado; crear/editar
   pago; botones dentro de la app para Pagué / Posponer / No lo pagaré. Aviso si faltan permisos.
5. **Metas y Deudas** — selector segmentado.
   - Meta: nombre, objetivo, fecha límite opcional, abonos; progreso y "necesitas ahorrar RD$X/mes".
   - Deuda: saldo original, saldo actual, tasa anual, cuota; progreso, fecha estimada de
     terminar, interés total restante; acciones "Abonar" y "Ajustar saldo".

**Ajustes:** categorías (crear/editar/archivar), hora por defecto de recordatorios,
exportar/importar respaldo, permisos de notificación.

Tema claro/oscuro según el sistema.

**Categorías por defecto**
- Gasto: Comida, Supermercado, Transporte, Combustible, Alquiler, Luz, Agua,
  Internet y teléfono, Salud, Educación, Entretenimiento, Ropa, Deudas, Otros.
- Ingreso: Sueldo, Extra, Otros ingresos.

## 4. Modelo de datos

Todos los montos se guardan como **enteros en centavos** (`int`). Fechas sin hora como `DateTime` a medianoche local.

| Tabla | Campos clave |
|---|---|
| `categories` | id, name, icon (codepoint), color (int), kind (`expense`/`income`), archived |
| `transactions` | id, kind (`income`/`expense`/`saving`), amountCents, categoryId?, date, note?, occurrenceId?, debtId?, goalId?, createdAt |
| `budgets` | id, categoryId, month (`YYYY-MM`), limitCents, alerted80, alerted100 — único (categoryId, month) |
| `planned_payments` | id, name, amountCents, categoryId, frequency (`once`/`weekly`/`biweekly`/`monthly`), anchorDate, remindHour, remindMinute, remindDaysBefore, debtId?, goalId?, active |
| `payment_occurrences` | id, plannedPaymentId, dueDate, status (`pending`/`paid`/`snoozed`/`skipped`), snoozedUntil?, transactionId? — único (plannedPaymentId, dueDate) |
| `goals` | id, name, targetCents, deadline?, createdAt, archived |
| `debts` | id, name, originalCents, balanceCents, annualRatePct (double), monthlyPaymentCents, createdAt, archived |

**Reglas**
- `saving` (abono a meta): cuenta como salida en el balance del mes, **no** consume presupuesto.
  Requiere `goalId`. Progreso de meta = suma de `saving` con ese `goalId`.
- Pago de deuda: `expense` con `debtId`; resta su monto completo de `balanceCents` (mínimo 0).
  "Ajustar saldo" cambia `balanceCents` directamente sin crear transacción.
- Un pago planeado ligado a meta genera `saving`; ligado a deuda o sin ligar genera `expense`.
- "Atrasado" no se guarda: es `pending` con `dueDate` < hoy (o `snoozed` con `snoozedUntil` < hoy).
- Borrar una transacción ligada revierte su efecto: suma de vuelta al saldo de la deuda y, si venía
  de una ocurrencia, la regresa a `pending`.
- Borrar un pago planeado = `active = false`; se cancelan sus notificaciones futuras y se borran sus
  ocurrencias `pending` futuras; el historial se conserva.

## 5. Lógica de dominio (Dart puro, `lib/domain/`)

- **Recurrencia** `dueDatesBetween(rule, from, to)`:
  - `once`: solo `anchorDate`.
  - `weekly`: cada 7 días desde `anchorDate`.
  - `biweekly` (quincenal): días 15 y último día de cada mes.
  - `monthly`: el día de `anchorDate`; si el mes es más corto, el último día del mes.
- **Proyección de deuda** `projectDebt(balance, annualRatePct, payment)`: simulación mes a mes
  (interés mensual = saldo × tasa/12/100, redondeado a centavos) hasta saldo 0, máximo 600 meses.
  Devuelve meses restantes, fecha estimada e interés total. Si la cuota ≤ interés del primer mes →
  resultado "la cuota no cubre el interés".
- **Estado de presupuesto** `budgetStatus(spent, limit)`: `ok` (< 80 %), `warning` (80–99 %), `over` (≥ 100 %).
- **Ritmo de meta** `monthlyNeeded(target, saved, deadline, today)`: (target − saved) / meses restantes
  (mínimo 1); `null` si no hay fecha límite o ya se cumplió.
- **Formato** `formatMoney(cents)` → `RD$2,500.00`; parseo de entrada a centavos.

## 6. Notificaciones

**Canales Android:** `pagos` (importancia alta, con acciones), `presupuesto` (normal),
`confirmaciones` (baja, desaparece sola a los 4 s).

**Programador (`PaymentScheduler.sync()`)** — se ejecuta al abrir la app, al volver a primer plano
y después de crear/editar/borrar pagos o responder una acción:
1. Para cada pago activo, crea las ocurrencias faltantes con `dueDate` entre hoy y hoy + 60 días.
2. Cancela solo las notificaciones **programadas** (`pendingNotificationRequests`; las ya visibles no
   se tocan, para no borrar un selector "¿Cuándo te recuerdo?" abierto) y vuelve a programar las de ocurrencias
   `pending` (fecha de aviso = dueDate − remindDaysBefore, a la hora del pago) y `snoozed`
   (en `snoozedUntil`, a la hora del pago), solo si la fecha de aviso es futura.
3. ID de notificación = id de la ocurrencia.

El plugin re-programa tras reinicio del teléfono (`RECEIVE_BOOT_COMPLETED`). Se solicita permiso
de notificaciones (Android 13+) y de alarmas exactas; sin alarmas exactas se programa en modo inexacto.

**Contenido:** "Luz · RD$2,500.00" / "Vence hoy" o "Vence el jue 10 oct".
Acciones: `[Pagué]` `[No pagué]` (ninguna abre la app).

**Acciones** (handler de segundo plano `@pragma('vm:entry-point')`, abre su propia conexión al
mismo archivo de base — `drift_flutter` con nombre `ag_finanzas`, modo WAL para tolerar dos
conexiones; el handler de primer plano usa el mismo código):
- **Pagué** → `PaymentActions.markPaid(occurrenceId)` → cancela la notificación → muestra
  "Registrado ✓ Luz RD$2,500.00" en `confirmaciones`.
- **No pagué** → reemplaza la notificación (mismo id) por "¿Cuándo te recuerdo? Luz · RD$2,500.00"
  con `[Mañana]` `[En 3 días]` `[No lo pagaré]`.
- **Mañana / En 3 días** → `PaymentActions.snooze(occurrenceId, days)` → programa el nuevo aviso.
- **No lo pagaré** → `PaymentActions.skip(occurrenceId)`.

Tocar el cuerpo de la notificación abre la app en la pestaña Pagos.

**Alertas de presupuesto:** después de registrar cualquier gasto (en la app o desde notificación),
si su categoría cruza 80 % o 100 % del límite del mes y no se había avisado (`alerted80`/`alerted100`),
se muestra una notificación en `presupuesto` y se marca la bandera. Editar el límite de una
categoría reinicia `alerted80` y `alerted100` de ese mes.

## 7. PaymentActions (núcleo transaccional)

Un único servicio usado por la UI y por las notificaciones. Cada operación corre en **una
transacción de base de datos**.

- `markPaid(occurrenceId, {amountCents?, date?})`: si ya está `paid`, no hace nada (idempotente).
  Si no: crea la transacción (`expense` o `saving` según la liga), la enlaza a la ocurrencia,
  marca `paid`, actualiza saldo de deuda si aplica. Luego evalúa alertas de presupuesto.
- `snooze(occurrenceId, days)`: solo si no está `paid`; `status = snoozed`, `snoozedUntil = hoy + days`.
- `skip(occurrenceId)`: solo si no está `paid`; `status = skipped`.

## 8. Manejo de errores

- Fallo en una acción en segundo plano → la ocurrencia queda como estaba, se muestra
  "No se pudo registrar. Abre la app." y el error se escribe en el log.
- Validación de formularios: monto > 0, nombre requerido, tasa entre 0 y 200, etc.; mensajes en español bajo el campo.
- Permisos negados → banner en Pagos con botón para conceder.
- **Respaldo:**
  - Exportar: JSON `{app: "ag_finanzas", schemaVersion, exportedAt, tables: {...}}` compartido con el menú del sistema.
  - Importar: valida `app` y `schemaVersion` (rechaza versiones más nuevas), guarda primero una copia
    automática de los datos actuales en la carpeta de la app, reemplaza todo en una transacción y
    ejecuta `PaymentScheduler.sync()`.

## 9. Estructura del código

```
lib/
  main.dart                  # init: timezone, notificaciones, DB, ProviderScope
  app/                       # router, tema, shell con navegación inferior
  domain/                    # lógica pura (sección 5), sin imports de Flutter
  data/
    database.dart            # AppDatabase (Drift), tablas, migraciones, seed de categorías
    tables.dart
    repositories/            # consultas por agregado (transacciones, presupuestos, pagos, metas, deudas)
  services/
    payment_actions.dart
    payment_scheduler.dart
    notification_service.dart  # canales, permisos, mostrar/programar, handlers
    backup_service.dart
  features/
    home/ transactions/ budget/ payments/ goals_debts/ settings/
      (pantallas, widgets y providers de cada una)
test/
  domain/  data/  services/  features/
```

## 10. Pruebas

- **Unitarias (domain):** recurrencia (quincenal, día 31, febrero, bisiesto), proyección de deuda
  (incluye cuota insuficiente y tasa 0), umbrales de presupuesto, ritmo de meta, formato y parseo de dinero.
- **Base de datos (Drift en memoria):** `markPaid` crea la transacción y actualiza deuda en una sola
  operación; doble `markPaid` no duplica; `snooze`/`skip`; borrar transacción revierte efectos;
  generación de ocurrencias sin duplicados; banderas de alerta de presupuesto; exportar → importar
  da el mismo contenido.
- **Widgets:** registro rápido, lista de movimientos, barras de presupuesto.
- **Manual en el teléfono:** recibir notificación, Pagué con la app cerrada, No pagué → Mañana,
  reinicio del teléfono.

## 11. Entrega

APK release instalado por USB (`adb install`) o compartiendo el archivo. Sin Play Store.
