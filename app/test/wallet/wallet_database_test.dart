import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WalletDatabase db;

  setUp(() => db = WalletDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('지출을 저장하면 그 나라 목록에 그대로 나온다', () async {
    await db.addExpense(
      isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD', amountMinor: 1200,
      krwPerUnitAtEntry: 8.4746, memo: '라멘', spentOn: DateTime(2026, 10, 9),
    );

    final rows = await db.watchExpenses('JP').first;

    expect(rows, hasLength(1));
    expect(rows.single.amountMinor, 1200);
    expect(rows.single.category, 'FOOD');
    expect(rows.single.krwPerUnitAtEntry, 8.4746);
    expect(rows.single.memo, '라멘');
    expect(rows.single.spentOn, DateTime(2026, 10, 9));
  });

  test('나라별로 나뉘고, 최근 날짜·나중 기록이 먼저 온다', () async {
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 100, spentOn: DateTime(2026, 10, 8));
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 200, spentOn: DateTime(2026, 10, 9));
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 300, spentOn: DateTime(2026, 10, 9));
    await db.addExpense(isoAlpha2: 'VN', currencyCode: 'VND', category: 'FOOD',
        amountMinor: 50000, spentOn: DateTime(2026, 10, 9));

    final rows = await db.watchExpenses('JP').first;

    expect(rows.map((r) => r.amountMinor).toList(), [300, 200, 100]);
  });

  test('지출을 수정하고 삭제할 수 있다', () async {
    final id = await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 1200, spentOn: DateTime(2026, 10, 9));
    final row = (await db.watchExpenses('JP').first).single;

    await db.updateExpense(row.copyWith(amountMinor: 1500, category: 'TRANSPORT'));
    final updated = (await db.watchExpenses('JP').first).single;
    expect(updated.amountMinor, 1500);
    expect(updated.category, 'TRANSPORT');

    await db.deleteExpense(id);
    expect(await db.watchExpenses('JP').first, isEmpty);
  });

  test('환전을 저장·수정·삭제할 수 있다', () async {
    final id = await db.addExchange(isoAlpha2: 'JP', currencyCode: 'JPY', amountMinor: 50000,
        krwPaid: 420000, memo: '공항 환전', exchangedOn: DateTime(2026, 10, 9));
    final row = (await db.watchExchanges('JP').first).single;
    expect(row.krwPaid, 420000);

    await db.updateExchange(row.copyWith(amountMinor: 60000));
    expect((await db.watchExchanges('JP').first).single.amountMinor, 60000);

    await db.deleteExchange(id);
    expect(await db.watchExchanges('JP').first, isEmpty);
  });

  test('지갑 비우기는 그 나라의 지출·환전만 지운다', () async {
    await db.addExpense(isoAlpha2: 'JP', currencyCode: 'JPY', category: 'FOOD',
        amountMinor: 1200, spentOn: DateTime(2026, 10, 9));
    await db.addExchange(isoAlpha2: 'JP', currencyCode: 'JPY', amountMinor: 50000,
        exchangedOn: DateTime(2026, 10, 9));
    await db.addExpense(isoAlpha2: 'VN', currencyCode: 'VND', category: 'FOOD',
        amountMinor: 50000, spentOn: DateTime(2026, 10, 9));

    await db.clearWallet('JP');

    expect(await db.watchExpenses('JP').first, isEmpty);
    expect(await db.watchExchanges('JP').first, isEmpty);
    expect(await db.watchExpenses('VN').first, hasLength(1));
  });
}
