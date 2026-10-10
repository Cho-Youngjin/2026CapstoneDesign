import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/wallet/data/exchange_rate.dart';
import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/widgets/rate_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_fixtures.dart';

Future<void> _pump(WidgetTester tester, String code, RateSnapshot? snap) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: RateBanner(currency: currencyInfoOf(code), snapshot: snap)),
  ));
}

void main() {
  testWidgets('수출입은행 환율은 표시 단위·등락·고시일을 보여준다', (tester) async {
    await _pump(tester, 'JPY', snapshot(rate: 8.4746, change: 0.42));

    expect(find.text('100엔 = 847.46원'), findsOneWidget);
    expect(find.text('▲ 0.42%'), findsOneWidget);
    expect(find.text('10월 8일 고시 · 한국수출입은행'), findsOneWidget);
    final change = tester.widget<Text>(find.byKey(const Key('rateBannerChange')));
    expect(change.style!.color, AppColors.warn);
  });

  testWidgets('하락은 파란색 ▼로 보인다', (tester) async {
    await _pump(tester, 'USD', snapshot(code: 'USD', rate: 1339.2, change: -0.31));

    expect(find.text('1달러 = 1,339.20원'), findsOneWidget);
    expect(find.text('▼ 0.31%'), findsOneWidget);
    final change = tester.widget<Text>(find.byKey(const Key('rateBannerChange')));
    expect(change.style!.color, AppColors.accent);
  });

  testWidgets('참고환율은 출처를 표기하고, 이전값이 없으면 등락을 생략한다', (tester) async {
    await _pump(tester, 'VND', snapshot(code: 'VND', rate: 0.051934, change: null,
        source: 'ER_API', baseDate: DateTime(2026, 10, 9)));

    expect(find.text('1,000동 = 51.93원'), findsOneWidget);
    expect(find.text('10월 9일 기준 · 참고환율 · Rates By Exchange Rate API'), findsOneWidget);
    expect(find.byKey(const Key('rateBannerChange')), findsNothing);
  });

  testWidgets('환율이 없으면 안내 문구를 보여준다', (tester) async {
    await _pump(tester, 'JPY', null);

    expect(find.text('환율 정보 없음 · 아래로 당겨 다시 시도'), findsOneWidget);
  });
}
