import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/wallet_entries.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

void main() {
  final d8 = DateTime(2026, 10, 8);
  final d9 = DateTime(2026, 10, 9);

  test('최근 날짜 먼저, 같은 날은 지출 다음 환전, 같은 종류는 나중 기록 먼저', () {
    final entries = buildWalletEntries(
      expenses: [expense(id: 1, amount: 100, on: d9), expense(id: 2, amount: 200, on: d9),
        expense(id: 3, amount: 300, on: d8)],
      exchanges: [exchange(id: 1, amount: 50000, on: d9)],
    );

    expect(entries.map(_describe).toList(), ['지출2', '지출1', '환전1', '지출3']);
  });

  test('카테고리 필터가 있으면 그 카테고리 지출만 남고 환전은 빠진다', () {
    final entries = buildWalletEntries(
      expenses: [expense(id: 1, amount: 100), expense(id: 2, category: ExpenseCategory.lodging, amount: 200)],
      exchanges: [exchange(id: 1, amount: 50000)],
      filter: ExpenseCategory.lodging,
    );

    expect(entries.map(_describe).toList(), ['지출2']);
  });

  test('날짜별로 묶는다', () {
    final entries = buildWalletEntries(
      expenses: [expense(id: 1, amount: 100, on: d9), expense(id: 2, amount: 200, on: d8)],
      exchanges: [exchange(id: 1, amount: 50000, on: d9)],
    );

    final groups = groupByDate(entries);

    expect(groups.map((g) => g.$1).toList(), [d9, d8]);
    expect(groups.first.$2, hasLength(2));
  });
}

String _describe(WalletEntry entry) => switch (entry) {
      ExpenseEntry(:final row) => '지출${row.id}',
      ExchangeEntry(:final row) => '환전${row.id}',
    };
