import 'trip_period.dart';
import 'trip_recorder.dart';

/// 여행 기록 서비스 한 번의 수명(설계 2026-11-07 9-2의 종료 규칙). 기록 서비스 isolate의 TaskHandler가 시작·5초 반복·
/// 종료를 넘기면, 이 객체가 기록기를 켜고 끄고 '스스로 끝낼 때'를 정한다. 플러그인을 부르지 않아 테스트가 시간을 넘긴다.
///
/// 끝낼 때(서비스를 끈다):
/// - 귀국일 다음 날 0시(기기 현지 시각)가 지났다 — 깰 때마다 본다
/// - 화면이 여행을 지웠거나 일시정지했다 — 저장소를 [checkEvery]마다 다시 읽어 본다(화면이 서비스를 바로 끄지만, 화면이
///   그 전에 꺼졌을 때를 대비한다)
class TripRecordingSession {
  TripRecordingSession({
    required this.trip,
    required this.openRecorder,
    required this.stillWanted,
    required this.clock,
    this.checkEvery = const Duration(minutes: 1),
  });

  final TripPeriod trip;
  final Future<TripRecorder> Function() openRecorder;

  /// 이 여행이 아직 일정에 있고 일시정지가 아닌가(저장소를 다시 읽는다).
  final Future<bool> Function() stillWanted;
  final DateTime Function() clock;
  final Duration checkEvery;

  TripRecorder? _recorder;
  DateTime? _lastCheck;
  bool _ended = false;

  /// 기록을 시작한다. 기간이 끝났거나 여행이 지워졌거나 일시정지면 시작하지 않고 false다(서비스를 끈다).
  Future<bool> start() async {
    final now = clock();
    _lastCheck = now;
    if (!trip.covers(now) || !await stillWanted()) {
      _ended = true;
      return false;
    }
    final recorder = await openRecorder();
    _recorder = recorder;
    await recorder.start();
    return true;
  }

  /// 반복 이벤트마다 부른다. 계속 기록하면 true, 끝낼 때면 기록기를 멈추고 false다(서비스를 끈다).
  Future<bool> tick() async {
    if (_ended) return false;
    final now = clock();
    var keep = trip.covers(now);
    final last = _lastCheck;
    if (keep && (last == null || now.difference(last) >= checkEvery)) {
      _lastCheck = now;
      keep = await stillWanted();
    }
    if (!keep) {
      await stop();
      return false;
    }
    await _recorder?.tick();
    return true;
  }

  /// 기록기를 멈춘다(열린 정지 구간을 닫고 남은 쓰기를 마친다). 여러 번 불러도 된다.
  Future<void> stop() async {
    _ended = true;
    final recorder = _recorder;
    _recorder = null;
    await recorder?.stop();
  }
}
