import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:footstep_core/footstep_core.dart' show createDetector, createPolicy;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/app_database.dart';
import '../data/checkin.dart';
import '../data/polygon_country_resolver.dart';
import '../map/world_geojson_parser.dart';
import '../recording/plugin_location_port.dart';
import '../recording/plugin_sensor_sources.dart';
import '../recording/policy_choice.dart';
import '../recording/recording_config.dart';
import '../recording/recording_mode.dart';
import 'trip_recorder.dart';
import 'trip_recording_session.dart';
import 'trip_recording_store.dart';

/// 여행 기록 서비스 isolate의 진입점. startService(callback:)로 넘기므로 top-level이어야 한다. 시스템이 서비스를 다시
/// 띄울 때도 이 함수가 다시 불린다(재부팅 뒤에는 autoRunOnBoot가 꺼져 있어 불리지 않는다).
@pragma('vm:entry-point')
void tripRecordingStartCallback() {
  FlutterForegroundTask.setTaskHandler(TripRecordingTaskHandler());
}

/// 여행 기록 모드의 서비스 본체(설계 4-1 `trip`). 화면과 다른 isolate에서 돌므로 Riverpod을 쓰지 않고 의존성을 직접 만든다.
/// 언제 끝낼지는 [TripRecordingSession]이, 무엇을 남길지는 [TripRecorder]가 정한다. 여기서는 플러그인을 이어 붙이기만 한다.
class TripRecordingTaskHandler extends TaskHandler {
  TripRecordingSession? _session;
  AppDatabase? _db;
  bool _stopping = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 이 isolate에서 Dart 쪽 등록이 필요한 플러그인(geolocator_android, shared_preferences 등)을 쓰려면 먼저 불러야 한다.
    DartPluginRegistrant.ensureInitialized();
    try {
      final raw = await FlutterForegroundTask.getData<String>(key: RecordingConfig.storageKey);
      final config =
          raw == null ? null : RecordingConfig.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      final trip = config?.trip;
      if (config == null || config.mode != RecordingMode.trip || trip == null) {
        await _stopService();
        return;
      }
      final store = TripRecordingStore(await SharedPreferences.getInstance());
      final db = AppDatabase();
      _db = db;
      final choice = config.policy ?? tripPolicyChoice;
      DateTime utcNow() => DateTime.now().toUtc();
      final session = TripRecordingSession(
        trip: trip,
        clock: DateTime.now,
        stillWanted: () => _stillWanted(store, trip.tripId),
        openRecorder: () async => TripRecorder(
          trip: trip,
          db: db,
          sources: PluginSensorSources(clock: utcNow),
          clock: utcNow,
          countryOf: await _loadCountryResolver(),
          policy: createPolicy(choice.policyId, choice.policyParams),
          detector: createDetector(choice.detectorId, choice.detectorParams),
          location: GeolocatorLocationPort(clock: utcNow),
          scheduler: TimerWakeScheduler(clock: utcNow),
          needs: PolicySensorNeeds.of(choice),
          onError: (e) => debugPrint('여행 기록 오류: $e'),
        ),
      );
      _session = session;
      if (!await session.start()) await _stopService();
    } catch (e) {
      // 시작에 실패했는데 알림만 남아 있으면 기록되는 줄 안다. 이유를 남기고 서비스를 끈다.
      debugPrint('여행 기록을 시작하지 못했습니다: $e');
      await _stopService();
    }
  }

  /// 화면 isolate가 지우거나 일시정지했으면 false. 저장소를 읽지 못하면 기록을 끊지 않는다(true).
  static Future<bool> _stillWanted(TripRecordingStore store, int tripId) async {
    try {
      await store.reload();
      return store.readTrips().any((t) => t.tripId == tripId) && !store.readPaused().contains(tripId);
    } catch (e) {
      debugPrint('여행 기록 상태를 읽지 못했습니다: $e');
      return true;
    }
  }

  /// 세계지도 폴리곤으로 좌표의 나라를 가린다(실시간 경로와 같은 방법, 오프라인 동작). 읽지 못하면 늘 미확인(XX)이라
  /// 기록기가 여행의 나라로 둔다.
  static Future<Future<String> Function(double lat, double lng)> _loadCountryResolver() async {
    try {
      final content = await rootBundle.loadString('assets/geo/world_countries.geojson');
      return PolygonCountryResolver(parseWorldGeoJson(content)).resolveIso2;
    } catch (e) {
      debugPrint('세계지도를 읽지 못해 여행의 나라로 기록합니다: $e');
      return (lat, lng) async => Checkin.unknownCountry;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final session = _session;
    if (session == null || _stopping) return;
    unawaited(session.tick().then((keep) async {
      if (!keep) await _stopService();
    }).catchError((Object e) {
      debugPrint('여행 기록 tick 실패: $e');
    }));
  }

  Future<void> _stopService() async {
    if (_stopping) return;
    _stopping = true;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      await _session?.stop();
    } finally {
      await _db?.close();
    }
  }
}
