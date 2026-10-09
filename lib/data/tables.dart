import 'package:drift/drift.dart';

import '../domain/recurrence.dart';

enum CategoryKind { expense, income }

enum TxKind { income, expense, saving }

enum OccurrenceStatus { pending, paid, snoozed, skipped }

@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  TextColumn get kind => textEnum<CategoryKind>()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('Goal')
class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get targetCents => integer()();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('Debt')
class Debts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get originalCents => integer()();
  IntColumn get balanceCents => integer()();
  RealColumn get annualRatePct => real()();
  IntColumn get monthlyPaymentCents => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('PlannedPayment')
class PlannedPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get amountCents => integer()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get frequency => textEnum<Frequency>()();
  DateTimeColumn get anchorDate => dateTime()();
  IntColumn get remindHour => integer()();
  IntColumn get remindMinute => integer()();
  IntColumn get remindDaysBefore => integer().withDefault(const Constant(0))();

  /// Días de la semana en que aplica un pago `daily` (máscara, lunes = 1 … domingo = 64).
  IntColumn get weekdays => integer().withDefault(const Constant(weekdaysAll))();
  IntColumn get debtId => integer().nullable().references(Debts, #id)();
  IntColumn get goalId => integer().nullable().references(Goals, #id)();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Último día hasta el que ya se generaron ocurrencias. `null` = generar desde hoy o el ancla.
  DateTimeColumn get generatedUntil => dateTime().nullable()();
}

@DataClassName('PaymentOccurrence')
class PaymentOccurrences extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get plannedPaymentId => integer().references(PlannedPayments, #id)();
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get status => textEnum<OccurrenceStatus>().withDefault(Constant(OccurrenceStatus.pending.name))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {plannedPaymentId, dueDate},
      ];
}

@DataClassName('Txn')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<TxKind>()();
  IntColumn get amountCents => integer()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  IntColumn get occurrenceId => integer().nullable().references(PaymentOccurrences, #id)();
  IntColumn get debtId => integer().nullable().references(Debts, #id)();
  IntColumn get goalId => integer().nullable().references(Goals, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Budget')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get month => text().withLength(min: 7, max: 7)();
  IntColumn get limitCents => integer()();
  BoolColumn get alerted80 => boolean().withDefault(const Constant(false))();
  BoolColumn get alerted100 => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {categoryId, month},
      ];
}

@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
