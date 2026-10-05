import '../data/checkin.dart';

/// 어떤 순간이든 그 순간이 속한 **로컬 달력 날짜의 자정**으로 접는다.
///
/// 하루 걸음 수는 Health Connect에서 로컬 자정~자정 구간 합계로 읽어오므로
/// (`health_steps_service.dart`의 `stepsOn`), 귀속 국가 판정과 `DailySteps`의
/// 날짜 키도 같은 기준이어야 한다. 발걸음 기록은 UTC로 저장되니 먼저 로컬로 돌린다.
///
/// 시각을 그대로 날짜 키로 쓰면 탭을 다시 열 때마다 값이 달라져 같은 날 행이
/// 여러 개 쌓이고, 누적 걸음 수가 스냅샷마다 중복 합산된다.
DateTime dayKeyOf(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// [date]가 속한 로컬 날짜에 기록된 체크인 중 가장 많이 등장한 국가를 반환한다.
/// 동률이면 그날 가장 이른 체크인의 국가를 쓴다. 체크인이 없으면 null.
String? attributeCountryForDate(DateTime date, List<Checkin> allCheckins) {
  final day = dayKeyOf(date);
  final sameDay = allCheckins.where((c) => dayKeyOf(c.recordedAt) == day).toList()
    ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

  if (sameDay.isEmpty) return null;

  final counts = <String, int>{};
  for (final c in sameDay) {
    counts.update(c.countryIso, (v) => v + 1, ifAbsent: () => 1);
  }

  final maxCount = counts.values.reduce((a, b) => a > b ? a : b);
  for (final c in sameDay) {
    if (counts[c.countryIso] == maxCount) return c.countryIso;
  }
  return null; // 도달하지 않음
}
