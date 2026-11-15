import 'dart:async';
import 'dart:math' as math;

import 'package:footstep_core/footstep_core.dart';

import '../../../core/db/app_database.dart';
import '../data/checkin.dart';
import '../recording/policy_choice.dart';
import '../recording/sensor_samples.dart';
import 'trip_period.dart';

/// 여행 기록에 쓰는 정책·걸음 감지기(설계 2026-11-07 9-2). 제안 정책 step_budget, E = 50m로 시작한다.
/// E와 걸음 감지기 종류는 R6 정확도 분석과 배터리 실험으로 확정한다 — 바꿀 곳은 여기 하나다.
const tripPolicyChoice = PolicyChoice(
  policyId: 'step_budget',
  policyParams: {'e_m': '50'},
  detectorId: 'adaptive',
);

/// 여행 기록 모드(설계 4-1 `trip`, 9-2·9-3). 정책 실행 모드(R4)와 같은 폰 실행기(PolicyRunner)로 제안 정책을 돌리되,
/// 세션 파일 대신 앱 DB에 쓴다.
/// - 정책에 알린 위치 → RoutePoints 한 행(여행 id·정확도·직전 점 이후 걸음 수·정책 상태). 국가는 [countryOf]로 가리고,
///   모르면(바다 위 등) 여행의 나라로 둔다.
/// - 걸음 감지기의 정지 구간 → TripStillSpans 한 행. 재생기와 같은 규칙(첫 분류 포함, 상태가 바뀐 순간)으로 잡는다.
///
/// 쓰기는 순서대로 하나씩 한다(같은 연결). 쓰기·센서 오류는 [onError]로 알리고 기록은 계속한다. 타이머를 안에 두지 않고,
/// 기록 서비스가 5초마다 [tick]을 부른다.
class TripRecorder {
  TripRecorder({
    required this.trip,
    required this.db,
    required this.sources,
    required this.clock,
    required this.countryOf,
    required CollectionPolicy policy,
    required this.detector,
    required LocationPort location,
    required WakeScheduler scheduler,
    required this.needs,
    this.onError,
    this.batteryInterval = const Duration(minutes: 1),
  }) {
    _runner = PolicyRunner(
      policy: policy,
      detector: detector,
      location: location,
      scheduler: scheduler,
      clock: () => clock().millisecondsSinceEpoch,
      sink: _TripSink(this),
      onError: (error, _) => _report(error),
      onStepUpdate: _onStepUpdate,
    );
  }

  final TripPeriod trip;
  final AppDatabase db;
  final SensorSources sources;
  final DateTime Function() clock;

  /// 좌표의 국가(ISO2). 기록 서비스에서는 세계지도 폴리곤으로 가린다(PolygonCountryResolver).
  final Future<String> Function(double lat, double lng) countryOf;
  final StepDetector detector;
  final PolicySensorNeeds needs;
  final void Function(Object error)? onError;

  /// 배터리 잔량을 읽는 간격. step_budget이 20% 미만에서 E를 2배로 키우는 데만 쓴다.
  final Duration batteryInterval;
  late final PolicyRunner _runner;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _writes = Future.value();
  bool _started = false;
  bool _stopped = false;
  DateTime? _lastBatteryAt;
  StepState? _detectorState;
  int? _stillSinceMs;

  /// 마지막으로 남긴 정지 구간의 끝. 시계가 거꾸로 가도 다음 구간이 겹치지 않게 시작을 여기까지 당긴다.
  int? _lastSpanEndMs;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _runner.start();
    if (needs.accel) {
      _listen(sources.accel(), (AccelSample s) {
        _runner.addAccel(AccelReading(tMs: s.at.millisecondsSinceEpoch, x: s.x, y: s.y, z: s.z));
      });
    }
    if (needs.osSteps) {
      _listen(sources.osSteps(), (OsStepSample s) {
        _runner.addOsStep(OsStepReading(tMs: s.at.millisecondsSinceEpoch, kind: s.kind, value: s.value));
      });
    }
    await _readBattery();
  }

  void _listen<T>(Stream<T> stream, void Function(T sample) onSample) {
    _subscriptions.add(stream.listen(onSample, onError: (Object e) => _report(e)));
  }

  /// 기록 서비스의 반복 이벤트(5초)마다 부른다.
  Future<void> tick() async {
    if (_stopped) return;
    // OS 센서판 감지기는 가속도 없이 이 주기를 시계로 써야 멈춘 뒤 정지로 바뀐다(PolicyRunner.advanceDetectorClock).
    if (needs.osSteps) _runner.advanceDetectorClock();
    final last = _lastBatteryAt;
    if (last == null || clock().difference(last) >= batteryInterval) await _readBattery();
  }

  /// 멈추고, 열려 있던 정지 구간을 지금으로 닫고, 맡긴 쓰기를 모두 마친다. 여러 번 불러도 한 번만 한다.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (e) {
        _report(e);
      }
    }
    _subscriptions.clear();
    await _runner.stop();
    _closeStill(clock().millisecondsSinceEpoch);
    await _writes;
  }

  void _savePoint(FixRecord record) {
    final steps = _drainSteps(record);
    _enqueue(() async {
      var iso = Checkin.unknownCountry;
      try {
        iso = await countryOf(record.fix.lat, record.fix.lng);
      } catch (e) {
        _report(e);
      }
      if (iso.length != 2 || iso == Checkin.unknownCountry) iso = trip.countryIso2;
      await db.insertTripPoint(
        tripId: trip.tripId,
        lat: record.fix.lat,
        lng: record.fix.lng,
        countryIso: iso,
        recordedAt: DateTime.fromMillisecondsSinceEpoch(record.tMs, isUtc: true),
        accuracyM: record.fix.accuracyM,
        stepsSincePrev: steps,
        state: record.state,
      );
    });
  }

  /// 직전 점 이후 걸음 수. 걸음 시각 목록(StepTimeline)을 내놓는 감지기는 점을 남길 때마다 그 목록을 비우고 비운 개수를 쓴다.
  /// - 목록을 아무도 비우지 않으면 하루 종일 걸을 때 메모리가 계속 자란다.
  /// - 점 뒤에 확인된 걸음(박자가 서야 소급해 세는 걸음 등)은 감지기의 실시간 값에서는 빠지지만 목록에는 남아, 사라지지
  ///   않고 다음 점의 걸음 수가 된다.
  /// 정책이 보는 값(감지기의 stepsSinceLastFix)은 건드리지 않는다. 목록이 없는 감지기는 그 값을 그대로 쓴다.
  /// 쓰기를 맡기기 전에(같은 동작 안에서) 불러야 다음 점이 같은 걸음을 다시 세지 않는다.
  int _drainSteps(FixRecord record) {
    if (detector case final StepTimeline timeline) {
      try {
        return timeline.takeStepTimes().length;
      } catch (e) {
        _report(e);
      }
    }
    return record.stepsSincePrev;
  }

  /// 상태가 바뀐 순간만 본다. 정지에 들어가면 시작 시각을 기억하고, 정지에서 나오면 그 구간을 남긴다.
  void _onStepUpdate(StepUpdate update) {
    final previous = _detectorState;
    if (previous == update.state) return;
    _detectorState = update.state;
    if (previous == StepState.still) _closeStill(update.tMs);
    if (update.state == StepState.still) {
      // 기기 시계가 거꾸로 가면 새 정지가 앞 구간 끝보다 이른 시각에 시작할 수 있다. 겹치는 구간은 정지 구간 계산이 거절하므로
      // 앞 구간이 끝난 시각으로 시작을 당긴다.
      final previousEnd = _lastSpanEndMs;
      _stillSinceMs = previousEnd == null ? update.tMs : math.max(update.tMs, previousEnd);
    }
  }

  void _closeStill(int endMs) {
    final startMs = _stillSinceMs;
    _stillSinceMs = null;
    if (startMs == null || endMs <= startMs) return;
    _lastSpanEndMs = endMs;
    _enqueue(() => db.insertTripStillSpan(
          tripId: trip.tripId,
          startAt: DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
          endAt: DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
        ));
  }

  Future<void> _readBattery() async {
    _lastBatteryAt = clock();
    try {
      final battery = await sources.readBattery();
      final level = battery.levelPct;
      // 정책이 배터리 20% 미만 대응을 할 수 있게 잔량을 알린다(바뀔 때만 — 실행기가 거른다).
      if (level != null) _runner.addBatteryLevel(battery.at.millisecondsSinceEpoch, level);
    } catch (e) {
      _report(e);
    }
  }

  void _enqueue(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).then((_) {}, onError: (Object e) => _report(e));
  }

  void _report(Object error) {
    try {
      onError?.call(error);
    } catch (_) {
      // 오류를 받는 곳의 오류까지 퍼뜨리면 기록이 멈춘다.
    }
  }
}

/// 실행기의 기록 중 위치만 DB에 남긴다. 할 일·깨우기 지연은 실험(정책 실행 모드)에서만 파일로 쓴다.
class _TripSink implements RunnerSink {
  _TripSink(this.recorder);

  final TripRecorder recorder;

  @override
  void fix(FixRecord record) => recorder._savePoint(record);

  @override
  void action(ActionRecord record) {}

  @override
  void wakeup(WakeupRecord record) {}
}
