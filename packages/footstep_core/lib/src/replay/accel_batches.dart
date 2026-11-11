import '../model/readings.dart';

/// 가속도를 [batchMs] 길이 묶음으로 모은다(실시간판). 앞 묶음이 시작된 뒤 [batchMs]가 지난 표본이 오면 앞 묶음을
/// 닫는다. 재생기([accelBatches])와 폰 실행기가 이 하나의 규칙을 같이 쓴다 — 제안 감지기의 출력은 묶음 크기에
/// 따라 달라져서(R3), 둘이 다르게 묶으면 재생 결과와 실기기 동작이 어긋난다.
class AccelBatcher {
  AccelBatcher(this.batchMs);

  final int batchMs;

  var _batch = <AccelReading>[];
  int? _windowStart;

  /// [reading]을 넣는다. 이 표본 때문에 앞 묶음이 닫히면 그 묶음을 돌려준다.
  List<AccelReading>? add(AccelReading reading) {
    final start = _windowStart ??= reading.tMs;
    List<AccelReading>? closed;
    if (reading.tMs - start >= batchMs && _batch.isNotEmpty) {
      closed = _batch;
      _batch = <AccelReading>[];
      _windowStart = reading.tMs;
    }
    _batch.add(reading);
    return closed;
  }

  /// 남은 표본을 마지막 묶음으로 돌려준다. 없으면 null이다.
  List<AccelReading>? flush() {
    if (_batch.isEmpty) return null;
    final rest = _batch;
    _batch = <AccelReading>[];
    _windowStart = null;
    return rest;
  }
}

/// 가속도를 [batchMs] 길이 묶음으로 나눈다([AccelBatcher]와 같은 규칙). 재생기와 걸음 감지 평가가 쓴다.
Iterable<List<AccelReading>> accelBatches(List<AccelReading> accel, int batchMs) sync* {
  final batcher = AccelBatcher(batchMs);
  for (final reading in accel) {
    final closed = batcher.add(reading);
    if (closed != null) yield closed;
  }
  final rest = batcher.flush();
  if (rest != null) yield rest;
}
