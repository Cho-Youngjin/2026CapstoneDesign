import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/visa_result_display.dart';
import 'package:flutter_test/flutter_test.dart';

VisaResult result({
  VisaVerdict verdict = VisaVerdict.visaFreeOk,
  int stayDays = 20,
  int? visaFreeDays = 45,
  bool passportOk = true,
  int? passportValidityMonths = 6,
  int? passportShortfallDays,
}) {
  return VisaResult(
    verdict: verdict,
    stayDays: stayDays,
    visaFreeDays: visaFreeDays,
    passportOk: passportOk,
    passportValidityMonths: passportValidityMonths,
    passportShortfallDays: passportShortfallDays,
  );
}

TripTask task({
  int id = 1,
  String title = '여권 재발급 신청',
  DateTime? dueDate,
  bool done = false,
}) {
  return TripTask(
    id: id,
    title: title,
    dueDate: dueDate ?? DateTime(2026, 9, 21),
    done: done,
  );
}

void main() {
  group('visaBadgeOf', () {
    test('무비자 한도 안이면 남은 여유를 게이지로 보여준다', () {
      final badge = visaBadgeOf(result());

      expect(badge.title, '무비자 45일');
      expect(badge.caption, '체류 20일 → 가능');
      expect(badge.tone, BadgeTone.info);
      expect(badge.gaugeFactor, closeTo(20 / 45, 0.001));
    });

    test('무비자 한도를 넘으면 초과를 알리고 게이지를 꽉 채운다', () {
      final badge = visaBadgeOf(
        result(verdict: VisaVerdict.visaFreeExceeded, stayDays: 60),
      );

      expect(badge.title, '무비자 45일 초과');
      expect(badge.caption, '체류 60일 → 비자 필요');
      expect(badge.tone, BadgeTone.warn);
      expect(badge.gaugeFactor, 1.0);
    });

    // 무비자가 애초에 불가한 국가다 — 무비자 일수를 보여주면 오해를 부른다.
    test('비자가 필요한 국가는 무비자 일수를 보여주지 않는다', () {
      final badge = visaBadgeOf(result(verdict: VisaVerdict.visaRequired));

      expect(badge.title, '비자 필요');
      expect(badge.caption, '체류 20일 · 무비자 불가');
      expect(badge.tone, BadgeTone.warn);
      expect(badge.gaugeFactor, isNull);
    });

    test('판정이 불가하면 영사관 확인으로 안내한다', () {
      final badge = visaBadgeOf(
        result(verdict: VisaVerdict.unverified, visaFreeDays: null),
      );

      expect(badge.title, '영사관 확인 필요');
      expect(badge.caption, '체류 20일 · 자동 판정 불가');
      expect(badge.tone, BadgeTone.neutral);
      expect(badge.gaugeFactor, isNull);
    });

    // 미검증 데이터로 "무비자 가능"이라고 단정하지 않는다는 원칙(CLAUDE.md)을
    // 화면에서도 한 번 더 지킨다 — 서버가 모순된 값을 주더라도 안전한 쪽으로 내린다.
    test('무비자 일수를 모르면 판정이 OK여도 영사관 확인으로 내린다', () {
      final badge = visaBadgeOf(result(visaFreeDays: null));

      expect(badge.title, '영사관 확인 필요');
      expect(badge.tone, BadgeTone.neutral);
    });
  });

  group('passportBadgeOf', () {
    test('요건을 충족하면 몇 개월 요건을 충족했는지 보여준다', () {
      final badge = passportBadgeOf(result());

      expect(badge.title, '여권 요건 충족');
      expect(badge.caption, '잔여 유효기간 6개월 요건 충족');
      expect(badge.tone, BadgeTone.info);
    });

    // passportValidityMonths == null은 "원문에 잔여기간 요건 언급이 없음"이라는
    // 뜻이다(서버 VisaJudgementService) — 판정 불가가 아니다.
    test('잔여기간 요건이 없는 국가는 요건 없음으로 안내한다', () {
      final badge = passportBadgeOf(result(passportValidityMonths: null));

      expect(badge.title, '여권 요건 충족');
      expect(badge.caption, '별도 잔여기간 요건 없음');
      expect(badge.tone, BadgeTone.info);
    });

    test('요건에 못 미치면 며칠 부족한지 보여준다', () {
      final badge = passportBadgeOf(
        result(passportOk: false, passportShortfallDays: 85),
      );

      expect(badge.title, '여권 재발급 필요');
      expect(badge.caption, '6개월 요건까지 85일 부족');
      expect(badge.tone, BadgeTone.warn);
    });

    test('잔여기간 요건이 없는데도 못 미치면 귀국일 기준으로 안내한다', () {
      final badge = passportBadgeOf(
        result(
          passportOk: false,
          passportValidityMonths: null,
          passportShortfallDays: 12,
        ),
      );

      expect(badge.title, '여권 재발급 필요');
      expect(badge.caption, '귀국일까지 12일 부족');
      expect(badge.tone, BadgeTone.warn);
    });
  });

  group('taskDateLabel', () {
    test('출발일까지 남은 일수를 D-day로 붙인다', () {
      expect(
        taskDateLabel(task(), departDate: DateTime(2026, 12, 20)),
        'D-90 · 09/21',
      );
    });

    test('출발 당일 항목은 D-0으로 표시한다', () {
      expect(
        taskDateLabel(
          task(dueDate: DateTime(2026, 12, 20)),
          departDate: DateTime(2026, 12, 20),
        ),
        'D-0 · 12/20',
      );
    });
  });

  group('taskToneOf', () {
    final now = DateTime(2026, 10, 6, 15);

    test('완료한 항목은 완료로 본다', () {
      expect(taskToneOf(task(done: true), now), TaskTone.done);
    });

    test('마감이 지났는데 안 했으면 급한 항목으로 본다', () {
      expect(
        taskToneOf(task(dueDate: DateTime(2026, 10, 5)), now),
        TaskTone.urgent,
      );
    });

    test('마감이 오늘인 항목은 아직 지난 것으로 보지 않는다', () {
      expect(
        taskToneOf(task(dueDate: DateTime(2026, 10, 6)), now),
        TaskTone.upcoming,
      );
    });

    test('마감이 남은 항목은 예정으로 본다', () {
      expect(
        taskToneOf(task(dueDate: DateTime(2026, 11, 5)), now),
        TaskTone.upcoming,
      );
    });
  });
}
