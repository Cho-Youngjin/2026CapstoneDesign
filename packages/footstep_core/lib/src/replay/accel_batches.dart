import '../model/readings.dart';

/// 가속도를 [batchMs] 길이 묶음으로 나눈다. 재생기와 걸음 감지 평가가 같은 묶음을 써야 두 결과에서 감지기가
/// 똑같이 동작한다(감지기는 묶음 끝 시각을 시계로 쓴다).
Iterable<List<AccelReading>> accelBatches(List<AccelReading> accel, int batchMs) sync* {
  var batch = <AccelReading>[];
  int? windowStart;
  for (final reading in accel) {
    final start = windowStart ??= reading.tMs;
    if (reading.tMs - start >= batchMs && batch.isNotEmpty) {
      yield batch;
      batch = <AccelReading>[];
      windowStart = reading.tMs;
    }
    batch.add(reading);
  }
  if (batch.isNotEmpty) yield batch;
}
