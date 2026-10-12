import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 JSON을 파싱하고 toJson으로 되돌리면 같은 값이 된다', () {
    final json = {
      'id': 3,
      'countryIso2': 'JP',
      'countryNameKo': '일본',
      'departDate': '2026-11-03',
      'returnDate': '2026-11-08',
      'verdict': 'VISA_FREE_OK',
    };

    final summary = TripSummary.fromJson(json);

    expect(summary.id, 3);
    expect(summary.countryNameKo, '일본');
    expect(summary.departDate, DateTime(2026, 11, 3));
    expect(summary.verdict, VisaVerdict.visaFreeOk);
    expect(summary.toJson(), json);
  });

  test('날짜 범위 라벨은 M/d~M/d 형식이다', () {
    final summary = TripSummary(
      id: 1,
      countryIso2: 'VN',
      countryNameKo: '베트남',
      departDate: DateTime(2026, 12, 20),
      returnDate: DateTime(2027, 1, 9),
      verdict: VisaVerdict.visaRequired,
    );

    expect(summary.dateRangeLabel, '12/20~1/9');
  });
}
