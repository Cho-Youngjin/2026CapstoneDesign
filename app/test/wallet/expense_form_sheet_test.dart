import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/widgets/expense_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

/// 버튼을 눌러 시트를 열고, 시트가 돌려준 값을 [results]에 담는다.
Future<List<ExpenseInput?>> _pumpOpener(WidgetTester tester,
    {String code = 'JPY', ExpenseRow? initial}) async {
  final results = <ExpenseInput?>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await showExpenseFormSheet(
            context,
            currency: currencyInfoOf(code),
            initial: initial,
            today: () => DateTime(2026, 10, 9, 18, 30),
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
  testWidgets('금액이 비어 있으면 오류를 보이고 닫히지 않는다', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('카테고리·금액·메모를 입력하면 그 값을 돌려준다(날짜는 오늘, 시각 제거)', (tester) async {
    final results = await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('category_SIGHTSEEING')));
    await tester.enterText(find.byKey(const Key('amountField')), '1,200');
    await tester.enterText(find.byKey(const Key('memoField')), '스카이트리');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    final input = results.single!;
    expect(input.category, ExpenseCategory.sightseeing);
    expect(input.amountMinor, 1200);
    expect(input.memo, '스카이트리');
    expect(input.spentOn, DateTime(2026, 10, 9));
  });

  testWidgets('통화보다 소수 자릿수가 많으면 오류', (tester) async {
    await _pumpOpener(tester, code: 'USD');

    await tester.enterText(find.byKey(const Key('amountField')), '12.345');
    await tester.tap(find.byKey(const Key('saveButton')));
    await tester.pumpAndSettle();

    expect(find.text('금액을 확인해 주세요'), findsOneWidget);
  });

  testWidgets('기타를 고르면 메모 힌트가 여행자보험·eSIM으로 바뀐다', (tester) async {
    await _pumpOpener(tester);

    await tester.tap(find.byKey(const Key('category_OTHER')));
    await tester.pump();

    final memo = tester.widget<TextField>(find.byKey(const Key('memoField')));
    expect(memo.decoration!.hintText, '여행자보험, eSIM 등');
  });

  testWidgets('수정 모드는 제목과 기존 값을 채운다', (tester) async {
    await _pumpOpener(tester,
        initial: expense(category: ExpenseCategory.lodging, amount: 16400, memo: '호텔'));

    expect(find.text('지출 수정'), findsOneWidget);
    expect(find.widgetWithText(TextField, '16400'), findsOneWidget);
    expect(find.widgetWithText(TextField, '호텔'), findsOneWidget);
  });
}
