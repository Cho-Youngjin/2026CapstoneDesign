import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/db/app_database.dart';
import '../../visa/models/trip_summary.dart';
import 'trip_departure_notices.dart';
import 'trip_period.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_service.dart';
import 'trip_recording_store.dart';

/// 화면(main isolate)에서 여행 기록을 켜고 끄는 곳(설계 2026-11-07 9-2). 무엇을 기록할지는 순수 함수 [shouldRecord]가
/// 정하고, 여기서는 그 결과에 기록 서비스를 맞춘다.
///
/// 켜는 것은 언제나 앱이 화면에 있을 때다 — Android 14가 백그라운드에서 위치 포그라운드 서비스를 켜는 것을 막는다.
/// 그래서 앱 셸이 앱을 열 때·포그라운드로 돌아올 때 [sync]를, 여행 목록을 받을 때 [updateTrips]를 부르고, 여행 상세의
/// 일시정지·재개가 [setPaused]를 부른다. 끄는 것은 여기(일시정지·기간 밖·정리)와 기록 서비스 자신(귀국 다음 날)이 한다.
///
/// 기록 정리(설계 9-3)도 여기서 한다. 비자 알람 정리(PR #32)와 같은 때에 부른다: 여행 삭제·없는 여행(404)은 [forgetTrip],
/// 목록을 다시 받을 때는 [updateTrips], 계정이 바뀔 때는 [claimFor].
///
/// 모든 작업은 부른 순서대로 하나씩 한다. 앱을 열자마자 목록이 도착하면 두 작업이 동시에 "꺼져 있다"고 보고 서비스를
/// 두 번 켜려 하고, 지우는 중인 여행을 다른 작업이 다시 켤 수 있기 때문이다.
class TripRecordingCoordinator {
  TripRecordingCoordinator({
    required this._store,
    required this._service,
    required this._permissions,
    required this._notices,
    required this._db,
    DateTime Function()? clock,
    this._onPausedChanged,
  }) : _clock = clock ?? DateTime.now;

  final TripRecordingStore _store;
  final TripRecordingService _service;
  final TripRecordingPermissions _permissions;
  final TripDepartureNotices _notices;
  final AppDatabase _db;
  final DateTime Function() _clock;

  /// 저장된 일시정지가 사용자 조작 밖에서 바뀔 수 있는 작업([updateTrips]·[forgetTrip]·[claimFor])이 끝날 때 부른다 —
  /// 일시정지 목록을 화면에 보여 주는 쪽이 저장소를 다시 읽게 하려는 것이다.
  final void Function()? _onPausedChanged;

  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {}); // 한 작업이 실패해도 다음 작업은 이어간다.
    return result;
  }

  /// [_serial]에 더해, 끝나면(실패해도) [_onPausedChanged]를 부른다.
  Future<void> _serialNotifying(Future<void> Function() action) => _serial(() async {
        try {
          await action();
        } finally {
          _onPausedChanged?.call();
        }
      });

  /// 기록 서비스를 지금(일정·일시정지·날짜)에 맞춘다.
  Future<void> sync() => _serial(_sync);

  /// 서버에서 받은 내 여행 목록으로 일정을 바꾼다. 출발일 알림과 기록 서비스를 먼저 맞추고(빠진 여행을 기록 중이면 끈다),
  /// 그 다음 목록에 없는 여행의 기록(좌표·정지 구간)을 지운다 — 다른 기기에서 지웠거나 다른 계정의 여행이다. 서비스를 먼저
  /// 끄는 것은 서비스가 끝나며 마지막으로 쓰는 점이 지운 뒤에 남지 않게 하려는 것이다. 오프라인 캐시 목록은 넘기지 않는다.
  ///
  /// 안전장치: 이전에 일정이 있었는데 목록이 비어 오면 기록은 지우지 않는다. 좌표는 서버에 없고 이 폰에만 있는 연구 데이터라
  /// (설계 9-3), 서버를 초기화했거나 서버 오류로 빈 목록이 와도 모든 여행의 좌표가 한꺼번에 사라지면 되돌릴 수 없다. 일정은
  /// 비우고 기록 서비스도 끈다. 사용자가 직접 지운 여행([forgetTrip])·계정 전환([claimFor])은 그대로 지운다.
  Future<void> updateTrips(List<TripSummary> trips) => _serialNotifying(() async {
        final periods = [for (final t in trips) TripPeriod.fromSummary(t)];
        final hadTrips = _store.readTrips().isNotEmpty;
        await _store.replaceTrips(periods);
        await _syncNotices();
        await _sync();
        if (periods.isEmpty && hadTrips) {
          debugPrint('빈 여행 목록을 받아 여행 기록(좌표)은 지우지 않았습니다.');
          return;
        }
        await _db.deleteTripRecordsExcept({for (final p in periods) p.tripId});
      });

  /// 저장된 일정에 곧 울릴 출발일 알림이 있는가. 앱 셸이 일정을 바꾼 뒤 알림 권한을 물을지 정하는 데 쓴다 — 국내 여행만
  /// 있는 사용자는 알림 권한을 묻는 비자 화면을 거치지 않기 때문이다.
  bool hasUpcomingNotice() => _notices.hasUpcoming(_store.readTrips(), _store.readPaused());

  /// 여행 상세의 일시정지·재개. 일시정지 상태는 여행별로 기기에 남는다. 일시정지한 여행은 출발일 알림도 없다.
  Future<void> setPaused(int tripId, bool paused) => _serial(() async {
        await _store.setPaused(tripId, paused);
        await _syncNotices();
        await _sync();
      });

  /// 여행이 없어졌을 때(삭제, 다른 기기에서 지워져 404): 그 여행을 기록 중이면 끄고, 좌표·정지 구간·일시정지·출발일
  /// 알림을 지운다. 서비스가 끝나며 마저 쓴 점이 남으면 다음 [updateTrips]가 지운다.
  Future<void> forgetTrip(int tripId) => _serialNotifying(() async {
        if (await _service.recordingTripId() == tripId) await _stopQuietly();
        await _db.deleteTripRecords([tripId]);
        await _store.forget({tripId});
        await _syncNotices();
      });

  /// 지금 로그인한 계정([uid], 로그아웃이면 null)을 기록의 주인으로 정한다(PR #32의 알람 주인과 같은 방식).
  /// - 같은 계정이면 아무것도 하지 않는다.
  /// - 로그아웃이면 기록을 끄고 일정·출발일 알림을 비운다. 좌표와 일시정지는 남긴다 — 같은 계정이 다시 로그인하면 그대로
  ///   보고, 멈춰 둔 여행이 몰래 다시 기록되지도 않는다(여행 id는 전체에서 유일하다).
  /// - 다른 계정이면 위에 더해 일시정지와 이전 계정의 여행 좌표·정지 구간을 모두 지운다.
  /// 주인이 적혀 있지 않으면(처음 실행) 지울 좌표가 없다고 보고 주인만 적는다.
  Future<void> claimFor(String? uid) => _serialNotifying(() async {
        final owner = _store.readOwner();
        if (uid != null && owner == uid) return;
        if (await _service.recordingTripId() != null) await _stopQuietly();
        await _store.clearTrips();
        try {
          await _notices.cancelAll();
        } catch (e) {
          debugPrint('출발일 알림을 지우지 못했습니다: $e');
        }
        if (uid == null) return;
        if (owner != null) {
          await _store.clearPaused();
          await _db.deleteTripRecordsExcept(const {});
        }
        await _store.writeOwner(uid);
      });

  /// 정리 중에 서비스를 끄다 실패해도(조회와 끄기 사이에 서비스가 스스로 끝난 경우 등) 정리는 이어간다.
  Future<void> _stopQuietly() async {
    try {
      await _service.stop();
    } catch (e) {
      debugPrint('여행 기록 서비스를 끄지 못했습니다: $e');
    }
  }

  /// 알림은 부가 기능이라 실패해도(플러그인·권한 오류) 기록을 맞추는 일은 막지 않는다.
  Future<void> _syncNotices() async {
    try {
      await _notices.sync(_store.readTrips(), _store.readPaused());
    } catch (e) {
      debugPrint('출발일 알림을 맞추지 못했습니다: $e');
    }
  }

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
