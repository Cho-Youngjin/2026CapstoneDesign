import 'package:intl/intl.dart';

/// 목표 환율 방향. 기본은 "이하로 내려가면"(싸게 환전하려는 경우가 대부분이다).
enum TargetDirection {
  below('BELOW', '이하'),
  above('ABOVE', '이상');

  const TargetDirection(this.code, this.labelKo);

  final String code;
  final String labelKo;

  static TargetDirection fromCode(String code) =>
      values.firstWhere((d) => d.code == code, orElse: () => below);
}

/// 목표 환율 하나(설계 §6.2). 사용자가 본 그대로 "100엔당 845원"을 [unit]·[targetKrw]로 저장한다 —
/// 나중에 환율이 바뀌어 표시 단위가 달라져도 목록에는 입력한 모양 그대로 보이게 하기 위해서다.
class RateTarget {
  const RateTarget({
    required this.id,
    required this.unit,
    required this.targetKrw,
    required this.direction,
    required this.active,
    required this.createdAt,
    this.firedAt,
  });

  /// 알림 id로도 쓴다(목표마다 알림 하나).
  final int id;

  /// 표시 단위 수량(1, 100, 1000).
  final int unit;

  /// [unit]당 목표 원화.
  final double targetKrw;
  final TargetDirection direction;

  /// false면 감시하지 않는다(도달해서 꺼졌거나 사용자가 껐다).
  final bool active;
  final DateTime createdAt;

  /// 도달해서 알림을 보낸 시각.
  final DateTime? firedAt;

  /// 1단위 기준 목표 원화(설계 §6.2 "1단위 기준으로 바꿔 저장").
  double get krwPerUnit => targetKrw / unit;

  RateTarget copyWith({bool? active, DateTime? firedAt, bool clearFiredAt = false}) => RateTarget(
        id: id,
        unit: unit,
        targetKrw: targetKrw,
        direction: direction,
        active: active ?? this.active,
        createdAt: createdAt,
        firedAt: clearFiredAt ? null : (firedAt ?? this.firedAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit': unit,
        'targetKrw': targetKrw,
        'direction': direction.code,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
        'firedAt': firedAt?.toIso8601String(),
      };

  factory RateTarget.fromJson(Map<String, dynamic> json) => RateTarget(
        id: json['id'] as int,
        unit: json['unit'] as int,
        targetKrw: (json['targetKrw'] as num).toDouble(),
        direction: TargetDirection.fromCode(json['direction'] as String),
        active: json['active'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
        firedAt: json['firedAt'] == null ? null : DateTime.parse(json['firedAt'] as String),
      );
}

/// 통화 하나의 알림 설정(설계 §6.2).
class RateAlertSettings {
  const RateAlertSettings({this.daily = false, this.lastDailyBaseDate, this.targets = const []});

  static const empty = RateAlertSettings();

  /// 매일 등락 알림.
  final bool daily;

  /// 등락 알림을 마지막으로 보낸 고시일. 같은 고시일로 두 번 보내지 않기 위해 둔다.
  final DateTime? lastDailyBaseDate;
  final List<RateTarget> targets;

  /// 백그라운드 작업이 이 통화를 감시해야 하는가.
  bool get isEnabled => daily || targets.any((t) => t.active);

  RateAlertSettings copyWith({bool? daily, DateTime? lastDailyBaseDate, List<RateTarget>? targets}) =>
      RateAlertSettings(
        daily: daily ?? this.daily,
        lastDailyBaseDate: lastDailyBaseDate ?? this.lastDailyBaseDate,
        targets: targets ?? this.targets,
      );

  Map<String, dynamic> toJson() => {
        'daily': daily,
        'lastDailyBaseDate': lastDailyBaseDate == null ? null : _isoDate(lastDailyBaseDate!),
        'targets': [for (final t in targets) t.toJson()],
      };

  factory RateAlertSettings.fromJson(Map<String, dynamic> json) => RateAlertSettings(
        daily: json['daily'] as bool? ?? false,
        lastDailyBaseDate: json['lastDailyBaseDate'] == null
            ? null
            : DateTime.parse(json['lastDailyBaseDate'] as String),
        targets: [
          for (final t in (json['targets'] as List<dynamic>? ?? const []))
            RateTarget.fromJson(t as Map<String, dynamic>),
        ],
      );

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 새 목표의 id. 안드로이드 알림 id는 32비트 정수라 10억 미만으로 자른다.
int newTargetId(DateTime now) => now.millisecondsSinceEpoch % 1000000000;

/// 목표 금액 표기: 850 → "850원", 1339.5 → "1,339.5원". 사용자가 입력한 모양에 가깝게 보여준다.
String formatTargetKrw(double won) => '${NumberFormat('#,##0.##', 'en_US').format(won)}원';
