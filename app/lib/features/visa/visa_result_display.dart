/// 비자 판정 결과를 화면 문구로 바꾸는 순수 함수들.
///
/// 색을 직접 들고 있지 않고 [BadgeTone]만 돌려준다 — 위젯 없이 문구/상태를
/// 단위 테스트로 검증할 수 있게 하려는 것이고, 색 토큰은 화면에서 입힌다.
library;

import 'models/trip.dart';

/// 배지의 강조 톤. 와이어프레임 색 토큰이 파랑(정보)/주황(주의)/회색(미확정)
/// 세 가지뿐이라 톤도 그 세 가지로 맞춘다.
enum BadgeTone { info, warn, neutral }

class ResultBadge {
  const ResultBadge({
    required this.title,
    required this.caption,
    required this.tone,
    this.gaugeFactor,
  });

  final String title;
  final String caption;
  final BadgeTone tone;

  /// 0.0~1.0. null이면 게이지를 그리지 않는다 — 비율로 말할 수 있는 값이
  /// 없을 때(비자 필요, 판정 불가) 의미 없는 막대를 그리지 않기 위함이다.
  final double? gaugeFactor;
}

/// 자동 판정이 불가할 때의 안내. 미검증 데이터로 "무비자 가능"이라고 단정하지
/// 않는다는 원칙(CLAUDE.md)에 따라, 모순된 응답도 전부 이쪽으로 내린다.
ResultBadge _consulateCheck(int stayDays) => ResultBadge(
      title: '영사관 확인 필요',
      caption: '체류 $stayDays일 · 자동 판정 불가',
      tone: BadgeTone.neutral,
    );

ResultBadge visaBadgeOf(VisaResult result) {
  final visaFreeDays = result.visaFreeDays;

  if (result.verdict == VisaVerdict.unverified) {
    return _consulateCheck(result.stayDays);
  }

  switch (result.verdict) {
    case VisaVerdict.visaRequired:
      return ResultBadge(
        title: '비자 필요',
        caption: '체류 ${result.stayDays}일 · 무비자 불가',
        tone: BadgeTone.warn,
      );

    case VisaVerdict.visaFreeOk:
      // 무비자 판정인데 한도를 모른다면 서버 응답이 모순된 상태다. 보여줄 숫자가
      // 없으므로 안전한 쪽(영사관 확인)으로 내린다.
      if (visaFreeDays == null) return _consulateCheck(result.stayDays);
      return ResultBadge(
        title: '무비자 $visaFreeDays일',
        caption: '체류 ${result.stayDays}일 → 가능',
        tone: BadgeTone.info,
        // 한도를 꽉 채운 경우도 초과가 아니므로(서버 판정이 `<=`) 1.0까지만 올린다.
        gaugeFactor: (result.stayDays / visaFreeDays).clamp(0.0, 1.0),
      );

    case VisaVerdict.visaFreeExceeded:
      if (visaFreeDays == null) return _consulateCheck(result.stayDays);
      return ResultBadge(
        title: '무비자 $visaFreeDays일 초과',
        caption: '체류 ${result.stayDays}일 → 비자 필요',
        tone: BadgeTone.warn,
        gaugeFactor: 1.0,
      );

    case VisaVerdict.unverified:
      return _consulateCheck(result.stayDays);
  }
}

ResultBadge passportBadgeOf(VisaResult result) {
  final months = result.passportValidityMonths;

  if (result.passportOk) {
    return ResultBadge(
      title: '여권 요건 충족',
      // months == null은 "원문에 잔여기간 요건 언급이 없음"이라는 뜻이다
      // (서버 VisaJudgementService.checkPassport) — 판정 불가가 아니다.
      caption: months == null ? '별도 잔여기간 요건 없음' : '잔여 유효기간 $months개월 요건 충족',
      tone: BadgeTone.info,
    );
  }

  final shortfall = result.passportShortfallDays;
  final String caption;
  if (shortfall == null) {
    caption = '여권 유효기간을 확인하세요';
  } else if (months == null) {
    // 잔여기간 요건이 없는데도 못 미쳤다면 "귀국일보다 먼저 만료"인 경우뿐이다.
    caption = '귀국일까지 $shortfall일 부족';
  } else {
    caption = '$months개월 요건까지 $shortfall일 부족';
  }

  return ResultBadge(
    title: '여권 재발급 필요',
    caption: caption,
    tone: BadgeTone.warn,
  );
}

/// 역산 일정 항목의 상태. 완료/급함/예정 세 가지다.
enum TaskTone { done, urgent, upcoming }

TaskTone taskToneOf(TripTask task, DateTime now) {
  if (task.done) return TaskTone.done;
  // 마감이 오늘인 항목은 아직 지난 것으로 보지 않는다(TripTask.isPastDueAt).
  return task.isPastDueAt(now) ? TaskTone.urgent : TaskTone.upcoming;
}

/// `D-90 · 09/21` — 출발일까지 남은 일수와 마감 날짜.
String taskDateLabel(TripTask task, {required DateTime departDate}) {
  final due = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
  final depart = DateTime(departDate.year, departDate.month, departDate.day);
  final daysBefore = depart.difference(due).inDays;
  final month = due.month.toString().padLeft(2, '0');
  final day = due.day.toString().padLeft(2, '0');
  return 'D-$daysBefore · $month/$day';
}
