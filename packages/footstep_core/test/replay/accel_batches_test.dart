import 'package:footstep_core/footstep_core.dart';
import 'package:footstep_core/src/replay/accel_batches.dart';
import 'package:test/test.dart';

void main() {
  test('묶음 길이만큼 시간이 지나면 새 묶음을 시작한다', () {
    final readings = [
      for (var t = 0; t <= 2500; t += 10) AccelReading(tMs: t, x: 0, y: 9.8, z: 0),
    ];
    final batches = accelBatches(readings, 1000).toList();
    expect(batches.map((b) => (b.first.tMs, b.last.tMs)), [(0, 990), (1000, 1990), (2000, 2500)]);
  });

  test('빈 목록이면 묶음이 없다', () {
    expect(accelBatches(const [], 1000), isEmpty);
  });

  test('AccelBatcher는 묶음이 닫힐 때만 돌려주고, flush로 남은 표본을 낸다(폰 실행기용 실시간판)', () {
    final batcher = AccelBatcher(1000);
    final closed = <(int, int)>[];
    for (var t = 0; t <= 2500; t += 10) {
      final batch = batcher.add(AccelReading(tMs: t, x: 0, y: 9.8, z: 0));
      if (batch != null) closed.add((batch.first.tMs, batch.last.tMs));
    }
    expect(closed, [(0, 990), (1000, 1990)]);
    final rest = batcher.flush()!;
    expect((rest.first.tMs, rest.last.tMs), (2000, 2500));
    expect(batcher.flush(), isNull);
  });
}
