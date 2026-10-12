import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/wallet_summary.dart';
import 'package:app/features/wallet/widgets/balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

Future<void> _pump(WidgetTester tester, WalletSummary summary, double? rate) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: BalanceCard(currency: currencyInfoOf('JPY'), summary: summary, krwPerUnit: rate),
    ),
  ));
}

void main() {
  final summary = WalletSummary.of(
    expenses: [expense(id: 1, amount: 1200), expense(id: 2, category: ExpenseCategory.lodging, amount: 16400)],
    exchanges: [exchange(amount: 50000)],
  );

  testWidgets('남은 돈과 현재 환율 원화 환산, 환전·지출 합계를 보여준다', (tester) async {
    await _pump(tester, summary, 8.4746);

    expect(find.text('남은 돈'), findsOneWidget);
    expect(find.text('¥32,400'), findsOneWidget);
    expect(find.text('≈ 274,577원'), findsOneWidget);
    expect(find.text('환전 ¥50,000 · 지출 ¥17,600'), findsOneWidget);
    expect(find.byKey(const Key('balanceGain')), findsNothing);
  });

  testWidgets('좁은 화면에서 큰 금액이어도 넘치지 않는다', (tester) async {
    final big = WalletSummary.of(
        expenses: const [], exchanges: [exchange(currency: 'VND', amount: 987654321)]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 220,
          child: BalanceCard(currency: currencyInfoOf('VND'), summary: big, krwPerUnit: 0.051934),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('₫987,654,321'), findsOneWidget);
  });

  testWidgets('낸 원화가 입력된 환전이 있으면 평가손익을 보여준다',(tester) async {
    final paid = WalletSummary.of(
        expenses: const [], exchanges: [exchange(amount: 50000, krwPaid: 420000)]);

    await _pump(tester, paid, 8.4746);

    expect(find.text('환전 평가손익 +3,730원'), findsOneWidget);
  });

  testWidgets('환율을 모르면 원화 환산을 생략한다', (tester) async {
    await _pump(tester, summary, null);

    expect(find.byKey(const Key('balanceKrw')), findsNothing);
    expect(find.text('¥32,400'), findsOneWidget);
  });
}
