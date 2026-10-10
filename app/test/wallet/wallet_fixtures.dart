import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:app/features/wallet/domain/expense_category.dart';

ExpenseRow expense({
  int id = 1,
  String iso = 'JP',
  String currency = 'JPY',
  ExpenseCategory category = ExpenseCategory.food,
  required int amount,
  double? krwAt,
  String memo = '',
  DateTime? on,
}) {
  return ExpenseRow(
    id: id,
    isoAlpha2: iso,
    currencyCode: currency,
    category: category.code,
    amountMinor: amount,
    krwPerUnitAtEntry: krwAt,
    memo: memo,
    spentOn: on ?? DateTime(2026, 10, 9),
  );
}

ExchangeRow exchange({
  int id = 1,
  String iso = 'JP',
  String currency = 'JPY',
  required int amount,
  int? krwPaid,
  String memo = '',
  DateTime? on,
}) {
  return ExchangeRow(
    id: id,
    isoAlpha2: iso,
    currencyCode: currency,
    amountMinor: amount,
    krwPaid: krwPaid,
    memo: memo,
    exchangedOn: on ?? DateTime(2026, 10, 9),
  );
}

RateSnapshot snapshot({
  String code = 'JPY',
  double rate = 8.4746,
  double? change = 0.42,
  String source = 'EXIM',
  DateTime? baseDate,
}) {
  return RateSnapshot(
    rate: ExchangeRate(
      currencyCode: code,
      krwRate: rate,
      baseDate: baseDate ?? DateTime(2026, 10, 8),
      changePercent: change,
      source: source,
    ),
    fetchedAt: DateTime(2026, 10, 9, 12),
  );
}
