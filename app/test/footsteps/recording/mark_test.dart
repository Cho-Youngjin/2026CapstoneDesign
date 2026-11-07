import 'package:app/features/footsteps/recording/mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 11, 9, 1, 2, 3);

  test('kind는 설계 문서의 csv 이름으로 오간다', () {
    expect(MarkKind.countStart.csvName, 'count_start');
    expect(MarkKind.countEnd.csvName, 'count_end');
    for (final kind in MarkKind.values) {
      expect(MarkKind.fromCsvName(kind.csvName), kind);
    }
  });

  test('Mark는 csv 행과 json으로 바뀐다', () {
    final mark = Mark(at: at, kind: MarkKind.board, value: VehicleType.bus);

    expect(mark.toCsvRow(), [at.millisecondsSinceEpoch, 'board', 'bus']);
    final back = Mark.fromJson(mark.toJson());
    expect(back.at, at);
    expect(back.kind, MarkKind.board);
    expect(back.value, 'bus');
  });

  test('알림 버튼 토글: 다음 표시를 만들 뿐 상태는 observe에서만 바뀐다', () {
    final field = FieldState();
    expect(field.placeButtonLabel, '도착');

    final arrive = field.nextPlaceMark(at);
    expect(arrive.kind, MarkKind.arrive);
    expect(field.atPlace, isFalse);

    field.observe(arrive);
    expect(field.atPlace, isTrue);
    expect(field.placeButtonLabel, '출발');
    expect(field.nextPlaceMark(at).kind, MarkKind.depart);
  });

  test('탑승 토글은 종류 미지정(vehicle)으로 표시하고, 다음은 하차다', () {
    final field = FieldState();
    expect(field.vehicleButtonLabel, '탑승');

    final board = field.nextVehicleMark(at);
    expect(board.kind, MarkKind.board);
    expect(board.value, VehicleType.unspecified);

    field.observe(board);
    expect(field.vehicleButtonLabel, '하차');
    final alight = field.nextVehicleMark(at);
    expect(alight.kind, MarkKind.alight);
    expect(alight.value, '');
  });

  test('화면에서 남긴 버스 탑승·출발도 같은 상태를 바꾼다', () {
    final field = FieldState()
      ..observe(Mark(at: at, kind: MarkKind.arrive))
      ..observe(Mark(at: at, kind: MarkKind.board, value: VehicleType.bus));
    expect(field.atPlace, isTrue);
    expect(field.onVehicle, isTrue);

    field
      ..observe(Mark(at: at, kind: MarkKind.depart))
      ..observe(Mark(at: at, kind: MarkKind.alight));
    expect(field.atPlace, isFalse);
    expect(field.onVehicle, isFalse);
  });

  test('걸음 세기·휴대 위치·메모는 현장 상태를 바꾸지 않는다', () {
    final field = FieldState()
      ..observe(Mark(at: at, kind: MarkKind.countStart))
      ..observe(Mark(at: at, kind: MarkKind.carry, value: CarryPosition.bag))
      ..observe(Mark(at: at, kind: MarkKind.note, value: '비 옴'));
    expect(field.atPlace, isFalse);
    expect(field.onVehicle, isFalse);
  });
}
