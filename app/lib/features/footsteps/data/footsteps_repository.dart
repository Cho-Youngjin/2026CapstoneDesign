import 'package:geolocator/geolocator.dart';

import '../../../core/db/app_database.dart';
import 'checkin.dart';
import 'country_resolver.dart';
import 'daily_step.dart';
import 'route_point.dart';

class FootstepsRepository {
  // 생성자 매개변수(db/countryResolver)가 필드명(_db/_countryResolver)과
  // 달라 initializing formal을 쓰면 외부에서 참조하는 named parameter 이름이
  // private으로 바뀌어 기존 호출부가 깨진다 — 의도적으로 이 형태를 유지한다.
  FootstepsRepository({required AppDatabase db, required CountryResolver countryResolver})
      : _db = db, // ignore: prefer_initializing_formals
        _countryResolver = countryResolver; // ignore: prefer_initializing_formals

  final AppDatabase _db;
  final CountryResolver _countryResolver;

  /// "여기 저장" 버튼. 위치 권한을 확인·요청하고 현재 좌표를 기록한다.
  Future<void> recordManualCheckin() async {
    final position = await _ensureLocationAndGetPosition();
    await recordCheckinAt(
      position.latitude,
      position.longitude,
      DateTime.now().toUtc(),
      CheckinSource.manual,
    );
  }

  /// 좌표가 이미 있는 경우(WorkManager, Timeline 임포트)의 공통 저장 경로.
  Future<void> recordCheckinAt(
    double lat,
    double lng,
    DateTime at,
    CheckinSource source,
  ) async {
    final iso = await _countryResolver.resolveIso2(lat, lng);
    await _db.insertCheckin(
      lat: lat,
      lng: lng,
      countryIso: iso,
      recordedAt: at,
      source: source,
    );
  }

  /// 실시간 이동 중 좌표 하나를 영구 기록한다. 국경 이동 확정과 무관하게
  /// 촘촘히 쌓여 나중에 "지나온 길"을 다시 그릴 수 있게 한다.
  Future<void> recordRoutePoint(double lat, double lng, String countryIso, DateTime at) =>
      _db.insertRoutePoint(lat: lat, lng: lng, countryIso: countryIso, recordedAt: at);

  Future<List<RoutePoint>> routePointsForCountry(String iso) => _db.routePointsForCountry(iso);

  Future<List<Checkin>> allCheckins() => _db.allCheckins();

  Future<List<Checkin>> checkinsForCountry(String iso) => _db.checkinsForCountry(iso);

  Future<Map<String, int>> cumulativeStepsByCountry() => _db.cumulativeStepsByCountry();

  Future<List<Checkin>> unsyncedCheckins() => _db.unsyncedCheckins();

  Future<void> markCheckinSynced(int id, String serverId) => _db.markCheckinSynced(id, serverId);

  Future<List<DailyStep>> unsyncedDailySteps() => _db.unsyncedDailySteps();

  Future<void> markDailyStepsSynced(int id, String serverId) =>
      _db.markDailyStepsSynced(id, serverId);

  Future<void> upsertDailySteps(DateTime date, String iso, int stepCount) =>
      _db.upsertDailySteps(date, iso, stepCount);

  Future<Position> _ensureLocationAndGetPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('위치 권한이 거부되었습니다. 설정에서 허용해 주세요.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('위치 서비스(GPS)가 꺼져 있습니다.');
    }
    // timeLimit 없이는 fused location이 새 fix를 못 받을 때(에뮬레이터에서 특히 흔함)
    // Future가 영원히 끝나지 않는다 — 대기 화면이 무한정 멈추는 대신 타임아웃으로
    // 실패시켜 사용자가 재시도할 수 있게 한다.
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // 개발/테스트는 에뮬레이터로 진행 중 — .medium은 raw GPS를 켜지 않아
        // 에뮬레이터 주입 좌표가 전달되지 않는다. 실기기 배포 전 .medium으로 되돌릴 것.
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }
}
