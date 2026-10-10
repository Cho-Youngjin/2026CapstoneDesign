import 'package:app/core/network/country_detail_api.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:app/features/wallet/data/wallet_rate.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/wallet_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

Future<void> _pumpWallet(
  WidgetTester tester, {
  RateSnapshot? rate,
  List<ExpenseRow> expenses = const [],
  List<ExchangeRow> exchanges = const [],
  String? currencyCode = 'JPY',
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      countryDetailProvider.overrideWith((ref, iso) async => CountryDetail(
            isoAlpha2: 'JP',
            nameKo: '일본',
            currencyCode: currencyCode,
            cardAcceptance: 'MEDIUM',
          )),
      walletRateProvider.overrideWith((ref, code) => Stream<RateSnapshot?>.value(rate)),
      walletExpensesProvider.overrideWith((ref, iso) => Stream.value(expenses)),
      walletExchangesProvider.overrideWith((ref, iso) => Stream.value(exchanges)),
    ],
    child: const MaterialApp(home: Scaffold(body: WalletPage(isoAlpha2: 'JP'))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final sample = (
    expenses: [
      expense(id: 1, amount: 1200, krwAt: 8.4746, memo: '라멘'),
      expense(id: 2, category: ExpenseCategory.lodging, amount: 16400, krwAt: 8.4746, memo: '호텔'),
    ],
    exchanges: [exchange(id: 1, amount: 50000, memo: '공항 환전')],
  );

  testWidgets('헤더·배너·남은 돈·기록 목록을 보여준다', (tester) async {
    await _pumpWallet(tester,
        rate: snapshot(), expenses: sample.expenses, exchanges: sample.exchanges);

    expect(find.text('일본 지갑'), findsOneWidget);
    expect(find.text('100엔 = 847.46원'), findsOneWidget);
    expect(find.text('¥32,400'), findsOneWidget);
    expect(find.text('환전 ¥50,000 · 지출 ¥17,600'), findsOneWidget);
    expect(find.text('라멘'), findsOneWidget);
    expect(find.text('≈ 10,170원'), findsOneWidget);
    expect(find.text('+¥50,000'), findsOneWidget);
    expect(find.text('≈ 423,730원'), findsOneWidget);
    expect(find.text('10월 9일'), findsOneWidget);
  });

  testWidgets('카테고리를 고르면 그 지출만 남고 환전은 빠진다', (tester) async {
    await _pumpWallet(tester,
        rate: snapshot(), expenses: sample.expenses, exchanges: sample.exchanges);

    await tester.tap(find.byKey(const Key('filter_LODGING')));
    await tester.pumpAndSettle();

    expect(find.text('호텔'), findsOneWidget);
    expect(find.text('라멘'), findsNothing);
    expect(find.text('+¥50,000'), findsNothing);
  });

  testWidgets('기록이 없으면 안내를 보여준다', (tester) async {
    await _pumpWallet(tester, rate: snapshot());

    expect(find.text('아직 기록이 없습니다. 아래 버튼으로 지출이나 환전을 기록해 보세요.'), findsOneWidget);
  });

  testWidgets('환율을 모르면 배너 안내와 기록의 "환율 없음"을 보여준다', (tester) async {
    await _pumpWallet(tester, expenses: [expense(id: 1, amount: 1200, memo: '라멘')]);

    expect(find.text('환율 정보 없음 · 아래로 당겨 다시 시도'), findsOneWidget);
    expect(find.text('환율 없음'), findsOneWidget);
  });

  testWidgets('나라에 통화 정보가 없으면 지갑을 쓸 수 없다고 안내한다', (tester) async {
    await _pumpWallet(tester, currencyCode: null);

    expect(find.text('이 나라의 통화 정보가 없어 지갑을 쓸 수 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('addExpenseButton')), findsNothing);
  });

  testWidgets('지출 기록 버튼은 지출 폼을, 환전 기록 버튼은 환전 폼을 연다', (tester) async {
    await _pumpWallet(tester, rate: snapshot());

    await tester.tap(find.byKey(const Key('addExpenseButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('amountField')), findsOneWidget);

    Navigator.of(tester.element(find.byKey(const Key('amountField')))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addExchangeButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exchangeAmountField')), findsOneWidget);
  });
}
