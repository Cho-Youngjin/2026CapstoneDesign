import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/wallet_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

void main() {
  final jpy = currencyInfoOf('JPY');

  test('환전·지출·잔액과 카테고리별 합계', () {
    final summary = WalletSummary.of(
      expenses: [
        expense(id: 1, amount: 1200),
        expense(id: 2, amount: 300),
        expense(id: 3, category: ExpenseCategory.lodging, amount: 16100),
      ],
      exchanges: [exchange(amount: 50000)],
    );

    expect(summary.exchangedMinor, 50000);
    expect(summary.spentMinor, 17600);
    expect(summary.balanceMinor, 32400);
    expect(summary.spentByCategory[ExpenseCategory.food], 1500);
    expect(summary.spentByCategory[ExpenseCategory.lodging], 16100);
    expect(summary.spentByCategory[ExpenseCategory.transport], 0);
  });

  test('평가손익은 낸 원화가 입력된 환전분만 현재 환율로 계산한다', () {
    final summary = WalletSummary.of(
      expenses: const [],
      exchanges: [
        exchange(id: 1, amount: 50000, krwPaid: 420000),
        exchange(id: 2, amount: 10000),
      ],
    );

    expect(summary.valuationGainKrw(jpy, 8.4746), 3730);
  });

  test('낸 원화 기록이 없거나 환율을 모르면 평가손익은 null', () {
    final noPaid = WalletSummary.of(expenses: const [], exchanges: [exchange(amount: 50000)]);
    final withPaid = WalletSummary.of(
        expenses: const [], exchanges: [exchange(amount: 50000, krwPaid: 420000)]);

    expect(noPaid.valuationGainKrw(jpy, 8.4746), isNull);
    expect(withPaid.valuationGainKrw(jpy, null), isNull);
  });
}
