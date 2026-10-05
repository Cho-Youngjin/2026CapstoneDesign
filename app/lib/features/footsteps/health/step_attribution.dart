import '../data/checkin.dart';

/// [date](자정 기준, UTC)에 기록된 체크인 중 가장 많이 등장한 국가를 반환한다.
/// 동률이면 그날 가장 이른 체크인의 국가를 쓴다. 체크인이 없으면 null.
String? attributeCountryForDate(DateTime date, List<Checkin> allCheckins) {
  final sameDay = allCheckins.where((c) =>
      c.recordedAt.year == date.year &&
      c.recordedAt.month == date.month &&
      c.recordedAt.day == date.day).toList()
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
