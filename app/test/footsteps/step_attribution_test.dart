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
  test('그 날짜에 체크인이 가장 많은 국가를 반환한다', () {
    final date = DateTime.utc(2026, 12, 21);
    final checkins = [
      _checkin('VN', DateTime.utc(2026, 12, 21, 1)),
      _checkin('VN', DateTime.utc(2026, 12, 21, 10)),
      _checkin('JP', DateTime.utc(2026, 12, 21, 20)),
      _checkin('JP', DateTime.utc(2026, 12, 20, 23)), // 전날, 제외돼야 함
    ];

    expect(attributeCountryForDate(date, checkins), 'VN');
  });

  test('그 날짜에 체크인이 없으면 null을 반환한다', () {
    final date = DateTime.utc(2026, 12, 25);
    final checkins = [_checkin('VN', DateTime.utc(2026, 12, 21, 1))];

    expect(attributeCountryForDate(date, checkins), isNull);
  });

  test('동률이면 가장 이른 체크인의 국가를 반환한다', () {
    final date = DateTime.utc(2026, 12, 21);
    final checkins = [
      _checkin('JP', DateTime.utc(2026, 12, 21, 9)),
      _checkin('VN', DateTime.utc(2026, 12, 21, 15)),
    ];

    expect(attributeCountryForDate(date, checkins), 'JP');
  });
}
