import 'dart:async';

import 'package:app/features/footsteps/recording/sensor_samples.dart';
import 'package:app/features/footsteps/trip/trip_period.dart';
import 'package:footstep_core/footstep_core.dart';

/// 테스트용 여행 기간. 날짜는 시각 없는 달력 날짜로 준다.
TripPeriod period(int id, DateTime depart, DateTime ret, {String iso2 = 'KR', String nameKo = '대한민국'}) =>
    TripPeriod(tripId: id, countryIso2: iso2, countryNameKo: nameKo, departDate: depart, returnDate: ret);

/// 기록기에 넣을 센서 대역. 스트림에 직접 값을 흘리고, 배터리 읽기 횟수를 센다.
class FakeTripSensors implements SensorSources {
  FakeTripSensors(this.clock);

  final DateTime Function() clock;
  final accelController = StreamController<AccelSample>.broadcast();
  final stepsController = StreamController<OsStepSample>.broadcast();
  int batteryLevel = 80;
  int batteryReads = 0;

  @override
  Stream<GpsSample> gps() => const Stream.empty();

  @override
  Stream<AccelSample> accel() => accelController.stream;

  @override
  Stream<OsStepSample> osSteps() => stepsController.stream;

  @override
  Stream<ActivitySample> activity() => const Stream.empty();

  @override
  Future<BatterySample> readBattery() async {
    batteryReads++;
    return BatterySample(at: clock(), plugged: false, levelPct: batteryLevel);
  }

  void step(DateTime at, int total) =>
      stepsController.add(OsStepSample(at: at, kind: OsStepKind.count, value: '$total'));
}

/// 위치 요청을 붙잡아 두는 GPS 대역. 테스트가 응답을 직접 채운다.
class FakeTripLocation implements LocationPort {
  final requests = <Completer<Fix?>>[];

  @override
  Future<Fix?> currentFix({required int timeoutMs}) {
    final completer = Completer<Fix?>();
    requests.add(completer);
    return completer.future;
  }

  @override
  Stream<Fix> continuousFixes({required int intervalMs, required double distanceFilterM}) => const Stream.empty();
}

/// 예약만 받아 두는 타이머 대역(이 테스트들은 깨우기를 부르지 않는다).
class FakeTripScheduler implements WakeScheduler {
  final scheduled = <Object>[];

  @override
  Object schedule(int atMs, void Function() callback) {
    final handle = Object();
    scheduled.add(handle);
    return handle;
  }

  @override
  void cancel(Object handle) => scheduled.remove(handle);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);
