class DailyStep {
  const DailyStep({
    required this.id,
    required this.date,
    required this.countryIso,
    required this.stepCount,
    required this.synced,
    this.serverId,
  });

  final int id;

  /// 자정(00:00) 기준 날짜. 시간 정보는 버린다.
  final DateTime date;
  final String countryIso;
  final int stepCount;
  final bool synced;
  final String? serverId;
}
