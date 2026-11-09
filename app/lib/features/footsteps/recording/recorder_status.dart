/// 기록 서비스가 5초마다 화면에 보내는 상태. 실험 화면이 "센서가 지금 값을 내고 있는가"를 보여 준다.
class RecorderStatus {
  const RecorderStatus({
    required this.startedAt,
    required this.rowCounts,
    required this.errorCount,
    required this.atPlace,
    required this.onVehicle,
    this.carry,
    this.lastGpsAccuracyM,
    this.lastOsSteps,
    this.lastChargeUah,
    this.lastLevelPct,
  });

  final DateTime startedAt;

  /// 파일 이름 → 이번 실행에서 쓴 행 수.
  final Map<String, int> rowCounts;
  final int errorCount;
  final bool atPlace;
  final bool onVehicle;

  /// 서비스가 알고 있는 지금 휴대 위치. 화면이 이 값으로 선택 칩을 맞춘다.
  final String? carry;
  final double? lastGpsAccuracyM;
  final int? lastOsSteps;
  final int? lastChargeUah;
  final int? lastLevelPct;

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.millisecondsSinceEpoch,
        'rowCounts': rowCounts,
        'errorCount': errorCount,
        'atPlace': atPlace,
        'onVehicle': onVehicle,
        'carry': carry,
        'lastGpsAccuracyM': lastGpsAccuracyM,
        'lastOsSteps': lastOsSteps,
        'lastChargeUah': lastChargeUah,
        'lastLevelPct': lastLevelPct,
      };

  factory RecorderStatus.fromJson(Map<String, Object?> json) => RecorderStatus(
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int, isUtc: true),
        rowCounts: (json['rowCounts'] as Map).map((k, v) => MapEntry(k as String, v as int)),
        errorCount: json['errorCount'] as int,
        atPlace: json['atPlace'] as bool,
        onVehicle: json['onVehicle'] as bool,
        carry: json['carry'] as String?,
        lastGpsAccuracyM: (json['lastGpsAccuracyM'] as num?)?.toDouble(),
        lastOsSteps: json['lastOsSteps'] as int?,
        lastChargeUah: json['lastChargeUah'] as int?,
        lastLevelPct: json['lastLevelPct'] as int?,
      );
}
