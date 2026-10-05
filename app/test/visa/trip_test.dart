import 'package:app/features/visa/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // server/.../trip/TripResponse.java 의 JSON 모양과 동일하게 맞춘 샘플.
  const json = {
    'id': 1,
    'countryIso2': 'VN',
    'countryNameKo': '베트남',
    'departDate': '2026-12-20',
    'returnDate': '2027-01-09',
    'passportExpiry': '2027-03-15',
    'visaResult': {
      'verdict': 'VISA_FREE_OK',
      'stayDays': 20,
      'visaFreeDays': 45,
      'passportOk': false,
      'passportValidityMonths': 6,
      'passportShortfallDays': 11,
    },
    'tasks': [
      {'id': 101, 'title': '여권 재발급 신청', 'dueDate': '2026-09-21', 'done': false},
      {'id': 102, 'title': '항공권·숙소 확정', 'dueDate': '2026-11-05', 'done': false},
    ],
    'judgementStale': false,
  };

  test('Trip.fromJson이 판정 결과와 일정 목록을 파싱한다', () {
    final trip = Trip.fromJson(json);

    expect(trip.id, 1);
    expect(trip.countryIso2, 'VN');
    expect(trip.countryNameKo, '베트남');
    expect(trip.departDate, DateTime(2026, 12, 20));
    expect(trip.returnDate, DateTime(2027, 1, 9));
    expect(trip.passportExpiry, DateTime(2027, 3, 15));
    expect(trip.visaResult.verdict, VisaVerdict.visaFreeOk);
    expect(trip.visaResult.stayDays, 20);
    expect(trip.visaResult.visaFreeDays, 45);
    expect(trip.visaResult.passportOk, isFalse);
    expect(trip.visaResult.passportShortfallDays, 11);
    expect(trip.tasks, hasLength(2));
    expect(trip.tasks.first.title, '여권 재발급 신청');
    expect(trip.judgementStale, isFalse);
  });

  test('judgementStale이 true면 그대로 파싱한다', () {
    final trip = Trip.fromJson({...json, 'judgementStale': true});

    expect(trip.judgementStale, isTrue);
  });

  test('judgementStale 필드가 없으면 false로 본다', () {
    final withoutStale = Map<String, dynamic>.of(json)..remove('judgementStale');

    expect(Trip.fromJson(withoutStale).judgementStale, isFalse);
  });

  test('Tier B 미검증 국가처럼 nullable 필드가 null이어도 파싱한다', () {
    final trip = Trip.fromJson({
      ...json,
      'visaResult': {
        'verdict': 'UNVERIFIED',
        'stayDays': 20,
        'visaFreeDays': null,
        'passportOk': true,
        'passportValidityMonths': null,
        'passportShortfallDays': null,
      },
    });

    expect(trip.visaResult.verdict, VisaVerdict.unverified);
    expect(trip.visaResult.visaFreeDays, isNull);
    expect(trip.visaResult.passportValidityMonths, isNull);
  });

  test('알 수 없는 verdict 문자열은 unverified로 안전하게 degrade한다', () {
    final trip = Trip.fromJson({
      ...json,
      'visaResult': <String, dynamic>{
        ...json['visaResult'] as Map<String, dynamic>,
        'verdict': 'SOMETHING_NEW',
      },
    });

    expect(trip.visaResult.verdict, VisaVerdict.unverified);
  });

  test('VisaVerdict wire 값이 서버 enum과 일치한다', () {
    expect(
      VisaVerdict.values.map((v) => v.wireValue),
      ['VISA_FREE_OK', 'VISA_FREE_EXCEEDED', 'VISA_REQUIRED', 'UNVERIFIED'],
    );
  });

  test('replaceTask는 id가 같은 항목만 교체한다', () {
    final trip = Trip.fromJson(json);

    final updated = trip.replaceTask(trip.tasks.first.copyWith(done: true));

    expect(updated.tasks[0].done, isTrue);
    expect(updated.tasks[1].done, isFalse);
    expect(trip.tasks[0].done, isFalse, reason: '원본은 바뀌지 않아야 한다');
  });

  group('TripTask.isPastDueAt', () {
    final now = DateTime(2026, 9, 30, 18, 0);

    TripTask taskDue(DateTime due, {bool done = false}) =>
        TripTask(id: 1, title: '최종 서류 점검', dueDate: due, done: done);

    test('마감일이 어제이고 완료 전이면 true다', () {
      expect(taskDue(DateTime(2026, 9, 29)).isPastDueAt(now), isTrue);
    });

    test('마감일이 오늘이면 아직 지난 게 아니다', () {
      expect(taskDue(DateTime(2026, 9, 30)).isPastDueAt(now), isFalse);
    });

    test('마감일이 미래면 false다', () {
      expect(taskDue(DateTime(2026, 10, 1)).isPastDueAt(now), isFalse);
    });

    test('완료된 항목은 마감이 지나도 false다', () {
      expect(taskDue(DateTime(2026, 9, 29), done: true).isPastDueAt(now), isFalse);
    });
  });
}
