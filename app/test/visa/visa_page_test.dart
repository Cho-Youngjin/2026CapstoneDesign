import 'package:app/core/network/country_api.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_providers.dart';
import 'package:app/features/visa/visa_page.dart';
import 'package:app/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

const _vietnam = Country(
  isoAlpha2: 'VN',
  nameKo: '베트남',
  nameEn: 'Vietnam',
  tier: 'A',
);

/// 비자 탭 + 결과 화면 자리만 있는 최소 라우터로 VisaPage를 띄운다.
Future<ProviderContainer> _pumpVisaPage(
  WidgetTester tester, {
  required FakeTripApi api,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: AppRoutes.visa,
    routes: [
      GoRoute(
        path: AppRoutes.visa,
        builder: (_, _) => const Scaffold(body: VisaPage()),
      ),
      GoRoute(
        path: AppRoutes.visaResult,
        builder: (_, _) => const Scaffold(body: Text('결과 화면')),
      ),
    ],
  );

  final scope = ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tripApiProvider.overrideWithValue(api),
      countryListProvider.overrideWith((ref) async => [_vietnam]),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();

  return ProviderScope.containerOf(tester.element(find.byType(VisaPage)));
}

/// 날짜 입력칸을 눌러 달력을 열고, 기본 선택된 날짜 그대로 확인을 누른다.
Future<void> _confirmDefaultDate(WidgetTester tester, String fieldKey) async {
  await tester.tap(find.byKey(Key(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('countryField')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('베트남'));
  await tester.pumpAndSettle();

  await _confirmDefaultDate(tester, 'departDateField');
  await _confirmDefaultDate(tester, 'returnDateField');
  await _confirmDefaultDate(tester, 'passportExpiryField');
}

ElevatedButton _submitButton(WidgetTester tester) => tester.widget(
      find.descendant(
        of: find.byKey(const Key('submitTripButton')),
        matching: find.byType(ElevatedButton),
      ),
    );

void main() {
  group('stayDaysBetween', () {
    test('서버와 같이 출발일~귀국일 사이 일수를 센다 (12/20 → 1/9 = 20일)', () {
      expect(stayDaysBetween(DateTime(2026, 12, 20), DateTime(2027, 1, 9)), 20);
    });

    test('당일 귀국은 0일이다', () {
      expect(stayDaysBetween(DateTime(2026, 12, 20), DateTime(2026, 12, 20)), 0);
    });

    test('시각이 섞여 있어도 날짜만 비교한다', () {
      expect(
        stayDaysBetween(DateTime(2026, 12, 20, 23, 59), DateTime(2026, 12, 21, 0, 1)),
        1,
      );
    });
  });

  group('clampDate', () {
    test('last보다 뒤인 값은 last로 내린다', () {
      // 출발일을 앞으로 당기면 이미 고른 귀국일이 새 last를 넘을 수 있다.
      // 그대로 showDatePicker에 넘기면 initialDate <= lastDate assertion에서 터진다.
      final today = DateTime(2026, 10, 5);
      expect(
        clampDate(today.add(const Duration(days: 900)), today, today.add(const Duration(days: 730))),
        today.add(const Duration(days: 730)),
      );
    });

    test('first보다 앞선 값은 first로 올린다', () {
      final today = DateTime(2026, 10, 5);
      expect(
        clampDate(today.subtract(const Duration(days: 1)), today, today.add(const Duration(days: 730))),
        today,
      );
    });

    test('범위 안의 값은 그대로 둔다', () {
      final today = DateTime(2026, 10, 5);
      final inRange = today.add(const Duration(days: 10));
      expect(clampDate(inRange, today, today.add(const Duration(days: 730))), inRange);
    });
  });

  group('tripErrorMessage', () {
    DioException withStatus(int code) {
      final options = RequestOptions(path: '/api/trips');
      return DioException.badResponse(
        statusCode: code,
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: code),
      );
    }

    test('상태 코드별로 안내 문구를 고른다', () {
      expect(tripErrorMessage(withStatus(400)), contains('입력값'));
      expect(tripErrorMessage(withStatus(401)), contains('로그인'));
      expect(tripErrorMessage(withStatus(404)), contains('국가'));
    });

    test('연결 실패는 네트워크 안내를 보여준다', () {
      final error = DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/trips'),
        reason: 'refused',
      );
      expect(tripErrorMessage(error), contains('서버에 연결'));
    });

    test('알 수 없는 오류는 일반 문구를 보여준다', () {
      expect(tripErrorMessage(Exception('boom')), contains('저장하지 못했어요'));
    });
  });

  group('VisaPage', () {
    testWidgets('처음에는 입력이 비어 있고 판정 버튼이 비활성이다', (tester) async {
      await _pumpVisaPage(tester, api: FakeTripApi());

      expect(find.text('국가를 선택하세요'), findsOneWidget);
      expect(find.text('출발일과 귀국일을 선택하세요'), findsOneWidget);
      expect(_submitButton(tester).onPressed, isNull);
    });

    testWidgets('국가 시트에서 고른 국가가 입력칸에 표시된다', (tester) async {
      await _pumpVisaPage(tester, api: FakeTripApi());

      await tester.tap(find.byKey(const Key('countryField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('베트남'));
      await tester.pumpAndSettle();

      expect(find.text('베트남'), findsOneWidget);
      expect(find.text('VN · Tier A'), findsOneWidget);
    });

    testWidgets('모두 입력하고 제출하면 여행을 만들고 결과 화면으로 이동한다', (tester) async {
      final api = FakeTripApi(tripToReturn: sampleTrip(id: 42));
      final container = await _pumpVisaPage(tester, api: api);

      await _fillForm(tester);
      expect(find.text('체류 0일'), findsOneWidget);
      expect(_submitButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('submitTripButton')));
      await tester.pumpAndSettle();

      expect(api.createTripCalls, hasLength(1));
      final call = api.createTripCalls.single;
      final today = DateUtils.dateOnly(DateTime.now());
      expect(call['countryIso2'], 'VN');
      expect(call['departDate'], today);
      expect(call['returnDate'], today);

      expect(container.read(activeTripIdProvider), 42);
      expect(find.text('결과 화면'), findsOneWidget);
    });

    testWidgets('여권 만료일을 고르지 않고 확인하면 오늘이 선택된다', (tester) async {
      // 만료된 여권도 입력할 수 있어야 하므로 firstDate는 과거로 열어두지만,
      // 달력이 처음 열릴 때 그 과거 날짜가 선택돼 있으면 안 된다.
      final api = FakeTripApi();
      await _pumpVisaPage(tester, api: api);

      await _fillForm(tester);
      await tester.tap(find.byKey(const Key('submitTripButton')));
      await tester.pumpAndSettle();

      final today = DateUtils.dateOnly(DateTime.now());
      expect(api.createTripCalls.single['passportExpiry'], today);
    });

    testWidgets('서버가 거절하면 오류 문구를 보여주고 화면에 남는다', (tester) async {
      final api = FakeTripApi(createTripStatusCode: 400);
      final container = await _pumpVisaPage(tester, api: api);

      await _fillForm(tester);
      await tester.tap(find.byKey(const Key('submitTripButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tripFormError')), findsOneWidget);
      expect(find.text('입력값을 다시 확인해 주세요.'), findsOneWidget);
      expect(find.text('결과 화면'), findsNothing);
      expect(container.read(activeTripIdProvider), isNull);
      expect(_submitButton(tester).onPressed, isNotNull, reason: '다시 시도할 수 있어야 한다');
    });
  });
}
