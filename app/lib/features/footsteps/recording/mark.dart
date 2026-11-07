/// 관찰 표시 종류(설계 4-2 `marks.csv`). csvName은 분석이 읽는 계약이다.
enum MarkKind {
  arrive('arrive'),
  depart('depart'),
  board('board'),
  alight('alight'),
  countStart('count_start'),
  countEnd('count_end'),
  carry('carry'),
  note('note');

  const MarkKind(this.csvName);

  final String csvName;

  static MarkKind fromCsvName(String name) => values.firstWhere((k) => k.csvName == name);
}

/// `board` 표시의 값. 알림 버튼으로는 종류를 고를 수 없어 `vehicle`로 남긴다.
abstract final class VehicleType {
  static const bus = 'bus';
  static const subway = 'subway';
  static const unspecified = 'vehicle';
}

/// 휴대 위치(`carry` 표시 값, meta.json의 carryInitial). 위치에 따라 걸음 감지 결과가 달라서
/// 분석 때 나눠 본다(연구 자료 5-1).
abstract final class CarryPosition {
  static const hand = 'hand';
  static const pocket = 'pocket';
  static const bag = 'bag';
  static const all = [hand, pocket, bag];
}

class Mark {
  const Mark({required this.at, required this.kind, this.value = ''});

  final DateTime at;
  final MarkKind kind;
  final String value;

  List<Object?> toCsvRow() => [at.millisecondsSinceEpoch, kind.csvName, value];

  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'kind': kind.csvName,
        'value': value,
      };

  factory Mark.fromJson(Map<String, Object?> json) => Mark(
        at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int, isUtc: true),
        kind: MarkKind.fromCsvName(json['kind'] as String),
        value: json['value'] as String? ?? '',
      );
}

/// 지금 장소 안에 있는지, 탈것에 타 있는지. Android 알림 버튼은 최대 3개라서 도착/출발,
/// 탑승/하차를 버튼 하나씩으로 토글한다 — 다음 누름이 무엇인지 정하려면 지금 상태를 알아야 한다.
///
/// 상태는 [observe]에서만 바뀐다. 알림 버튼이든 화면 버튼이든 실제로 기록된 표시를 그대로 넣어,
/// 두 입력 경로가 서로 다른 상태를 보지 않게 한다.
class FieldState {
  bool atPlace = false;
  bool onVehicle = false;

  Mark nextPlaceMark(DateTime at) =>
      Mark(at: at, kind: atPlace ? MarkKind.depart : MarkKind.arrive);

  Mark nextVehicleMark(DateTime at) => onVehicle
      ? Mark(at: at, kind: MarkKind.alight)
      : Mark(at: at, kind: MarkKind.board, value: VehicleType.unspecified);

  void observe(Mark mark) {
    switch (mark.kind) {
      case MarkKind.arrive:
        atPlace = true;
      case MarkKind.depart:
        atPlace = false;
      case MarkKind.board:
        onVehicle = true;
      case MarkKind.alight:
        onVehicle = false;
      case MarkKind.countStart || MarkKind.countEnd || MarkKind.carry || MarkKind.note:
        break;
    }
  }

  String get placeButtonLabel => atPlace ? '출발' : '도착';

  String get vehicleButtonLabel => onVehicle ? '하차' : '탑승';
}
