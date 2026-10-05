import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/health/step_attribution.dart';
import 'package:flutter_test/flutter_test.dart';

Checkin _checkin(String iso, DateTime at) => Checkin(
      id: 0,
      lat: 0,
      lng: 0,
      countryIso: iso,
      recordedAt: at,
      source: CheckinSource.auto,
      synced: false,
    );

void main() {
  // 걸음 수는 Health Connect에서 "로컬 자정~자정" 구간 합계로 읽어온다
  // (health_steps_service.dart의 stepsOn). 그래서 귀속 국가와 DB 키도 같은
  // 로컬 달력 날짜를 써야 한다 — 아래 테스트들은 전부 로컬 시각으로 쓴다.
  group('dayKeyOf', () {
    test('같은 날의 어떤 시각이든 그 날 자정으로 접힌다', () {
      final midnight = DateTime(2026, 12, 21);

      expect(dayKeyOf(DateTime(2026, 12, 21)), midnight);
      expect(dayKeyOf(DateTime(2026, 12, 21, 13, 42, 7)), midnight);
      expect(dayKeyOf(DateTime(2026, 12, 21, 23, 59, 59)), midnight);
    });

    test('UTC로 저장된 순간도 로컬 달력 날짜로 접힌다', () {
      // 발걸음 기록은 UTC로 저장된다. 같은 순간을 UTC로 바꿔 넘겨도
      // 원래의 로컬 날짜가 나와야 한다.
      final instant = DateTime(2026, 12, 21, 13, 42);

      expect(dayKeyOf(instant.toUtc()), DateTime(2026, 12, 21));
    });
  });

  group('attributeCountryForDate', () {
    test('그 날짜에 체크인이 가장 많은 국가를 반환한다', () {
      final checkins = [
        _checkin('VN', DateTime(2026, 12, 21, 1)),
        _checkin('VN', DateTime(2026, 12, 21, 10)),
        _checkin('JP', DateTime(2026, 12, 21, 20)),
        _checkin('JP', DateTime(2026, 12, 20, 23)), // 전날, 제외돼야 함
      ];

      expect(attributeCountryForDate(DateTime(2026, 12, 21), checkins), 'VN');
    });

    test('그 날짜에 체크인이 없으면 null을 반환한다', () {
      final checkins = [_checkin('VN', DateTime(2026, 12, 21, 1))];

      expect(attributeCountryForDate(DateTime(2026, 12, 25), checkins), isNull);
    });

    test('동률이면 가장 이른 체크인의 국가를 반환한다', () {
      final checkins = [
        _checkin('JP', DateTime(2026, 12, 21, 9)),
        _checkin('VN', DateTime(2026, 12, 21, 15)),
      ];

      expect(attributeCountryForDate(DateTime(2026, 12, 21), checkins), 'JP');
    });

    test('그날 안의 어떤 시각을 넘겨도 결과가 같다', () {
      // 호출자가 DateTime.now()를 그대로 넘겨도 자정을 넘긴 것과 같아야 한다 —
      // 그렇지 않으면 탭을 다시 열 때마다 DailySteps 행이 새로 쌓인다.
      final checkins = [_checkin('VN', DateTime(2026, 12, 21, 10))];

      expect(attributeCountryForDate(DateTime(2026, 12, 21), checkins), 'VN');
      expect(attributeCountryForDate(DateTime(2026, 12, 21, 23, 59), checkins), 'VN');
    });

    test('UTC로 저장된 체크인도 로컬 날짜로 센다', () {
      final checkins = [_checkin('VN', DateTime(2026, 12, 21, 10).toUtc())];

      expect(attributeCountryForDate(DateTime(2026, 12, 21), checkins), 'VN');
    });
  });
}
