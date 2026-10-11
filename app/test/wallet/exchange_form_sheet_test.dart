import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/widgets/exchange_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<ExchangeInput?>> _pumpOpener(WidgetTester tester) async {
  final results = <ExchangeInput?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await showExchangeFormSheet(
            context,
            currency: currencyInfoOf('JPY'),
            today: () => DateTime(2026, 10, 9),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('받은 금액과 낸 원화를 돌려준다', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byKey(const Key('exchangeAmountField')), '50,000');
    await tester.enterText(find.byKey(const Key('krwPaidField')), '420,000');
    await tester.enterText(find.byKey(const Key('exchangeMemoField')), '공항 환전');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    final input = results.single!;
    expect(input.amountMinor, 50000);
    expect(input.krwPaid, 420000);
    expect(input.memo, '공항 환전');
    expect(input.exchangedOn, DateTime(2026, 10, 9));
  });

  testWidgets('낸 원화를 비우면 null', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byKey(const Key('exchangeAmountField')), '50000');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(results.single!.krwPaid, isNull);
  });

  testWidgets('낸 원화가 숫자가 아니면 오류', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.enterText(find.byKey(const Key('exchangeAmountField')), '50000');
    await tester.enterText(find.byKey(const Key('krwPaidField')), 'abc');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('원화 금액을 확인해 주세요'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('받은 금액이 없으면 오류', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect(results, isEmpty);
  });
}
