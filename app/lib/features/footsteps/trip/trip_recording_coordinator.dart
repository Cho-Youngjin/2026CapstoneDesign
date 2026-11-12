import '../../visa/models/trip_summary.dart';
import 'trip_period.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

/// 화면(main isolate)에서 여행 기록을 켜고 끄는 곳(설계 2026-11-07 9-2). 무엇을 기록할지는 순수 함수 [shouldRecord]가
/// 정하고, 여기서는 그 결과에 기록 서비스를 맞춘다.
///
/// 켜는 것은 언제나 앱이 화면에 있을 때다 — Android 14가 백그라운드에서 위치 포그라운드 서비스를 켜는 것을 막는다.
/// 그래서 앱 셸이 앱을 열 때·포그라운드로 돌아올 때 [sync]를, 여행 목록을 받을 때 [updateTrips]를 부르고, 여행 상세의
/// 일시정지·재개가 [setPaused]를 부른다. 끄는 것은 여기(일시정지·기간 밖)와 기록 서비스 자신(귀국 다음 날)이 한다.
///
/// 모든 작업은 부른 순서대로 하나씩 한다. 앱을 열자마자 목록이 도착하면 두 작업이 동시에 "꺼져 있다"고 보고 서비스를
/// 두 번 켜려 하기 때문이다.
class TripRecordingCoordinator {
  TripRecordingCoordinator({
    required this._store,
    required this._service,
    required this._permissions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TripRecordingStore _store;
  final TripRecordingService _service;
  final TripRecordingPermissions _permissions;
  final DateTime Function() _clock;

  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {}); // 한 작업이 실패해도 다음 작업은 이어간다.
    return result;
  }

  /// 기록 서비스를 지금(일정·일시정지·날짜)에 맞춘다.
  Future<void> sync() => _serial(_sync);

  /// 서버에서 받은 내 여행 목록으로 일정을 바꾸고 기록 서비스를 다시 맞춘다. 오프라인 캐시 목록은 넘기지 않는다.
  Future<void> updateTrips(List<TripSummary> trips) => _serial(() async {
        await _store.replaceTrips([for (final t in trips) TripPeriod.fromSummary(t)]);
        await _sync();
      });

  /// 여행 상세의 일시정지·재개. 일시정지 상태는 여행별로 기기에 남는다.
  Future<void> setPaused(int tripId, bool paused) => _serial(() async {
        await _store.setPaused(tripId, paused);
        await _sync();
      });

  Future<void> _sync() async {
    final running = await _service.isRunning();
    final active = running ? await _service.recordingTripId() : null;
    // 실험 화면의 세션이 돌고 있다. 같이 돌면 배터리 측정이 오염되므로(설계 4-1) 건드리지 않는다.
    if (running && active == null) return;
    final target = shouldRecord(_store.readTrips(), _clock(), _store.readPaused());
    if (active != null && active != target?.tripId) await _service.stop();
    if (target == null || active == target.tripId) return;
    // 위치 권한이 없으면 서비스가 켜지자마자 죽는다. 날짜별 보기의 "기록이 꺼져 있어요" 배너가 알린다.
    if (!await _permissions.canRecord()) return;
    await _service.start(target);
  }
}
