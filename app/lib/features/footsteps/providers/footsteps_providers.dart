import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x는 StateProvider를 legacy.dart로 분리했다(기본 barrel에서 제외됨).
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/db/app_database.dart';
import '../../../core/network/api_client.dart';
import '../data/country_resolver.dart';
import '../data/footsteps_api.dart';
import '../data/footsteps_repository.dart';
import '../data/footsteps_sync_service.dart';
import '../data/geocoding_country_resolver.dart';
import '../data/polygon_country_resolver.dart';
import '../health/health_steps_service.dart' show HealthStepsService, syncStepsToDatabase;
import '../health/step_attribution.dart' show dayKeyOf;
import '../map/live_route_tracker.dart';
import '../map/world_geojson_parser.dart';

final countryResolverProvider = Provider<CountryResolver>((ref) => GeocodingCountryResolver());

/// 세계지도 GeoJSON — 지도 렌더링과 실시간 국가 판정(PolygonCountryResolver)이
/// 함께 쓰므로 한 번만 로드해 공유한다.
final worldCountryPolygonsProvider = FutureProvider<List<CountryPolygon>>((ref) async {
  final content = await rootBundle.loadString('assets/geo/world_countries.geojson');
  return parseWorldGeoJson(content);
});

/// 실시간 스트림 전용 리졸버. 외부 API 없이 즉시 판정해야 해서 GeocodingCountryResolver
/// 대신 로컬 폴리곤 매칭을 쓴다(오프라인에서도 동작). GeoJSON이 아직 로드되지 않았으면
/// 로드될 때까지 미확인(XX)을 반환한다 — 로드가 끝나면 provider가 다시 빌드된다.
final realtimeCountryResolverProvider = Provider<CountryResolver>((ref) {
  final polygons = ref.watch(worldCountryPolygonsProvider).asData?.value ?? const [];
  return PolygonCountryResolver(polygons);
});

/// 발걸음 탭이 화면에 떠 있을 때만 켜는 실시간 추적 스위치. 앱이 백그라운드로
/// 가면 false로 내려 GPS 스트림을 끊는다(배터리 방어) — 다시 true가 되면
/// autoDispose provider가 재빌드되며 스트림을 새로 연다.
///
/// 국가 판정(체크인)은 원래 설계대로 WorkManager 1시간 주기(footstep_workmanager.dart)와
/// 포그라운드 수동 "여기 저장"만 쓴다 — 국경 이동을 실시간으로 자동 체크인하는
/// 기능은 만들지 않는다. 이 스위치는 아래 liveRouteProvider(실시간 이동 경로
/// 표시 전용)에만 쓰인다.
final realtimeTrackingEnabledProvider = StateProvider<bool>((ref) => true);

/// "지금 걷고 있는 경로"를 국가 판정과 무관하게 그대로 이어 그리기 위한 좌표 목록이자,
/// 각 좌표를 RoutePoints 테이블에 영구 저장하는 부수효과를 겸한다(live_route_tracker.dart).
/// 경로가 뚝뚝 끊기지 않도록 촘촘한(10m) distanceFilter로 구독한다. 반환하는
/// 좌표 목록 자체는 이번 구독 동안만 유효한 화면 표시용 캐시이고(화면을 벗어나면 autoDispose로 사라짐),
/// DB에 쌓인 기록은 앱을 껐다 켜도 남는다 — CountryDetailMapPage가 그 기록을 다시 읽는다.
final liveRouteProvider = StreamProvider.autoDispose<List<LatLng>>((ref) {
  final enabled = ref.watch(realtimeTrackingEnabledProvider);
  if (!enabled) return const Stream.empty();

  final positions = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  );

  return trackAndPersistLiveRoute(
    positions: positions,
    countryResolver: ref.watch(realtimeCountryResolverProvider),
    repository: ref.watch(footstepsRepositoryProvider),
  );
});

final footstepsRepositoryProvider = Provider<FootstepsRepository>((ref) {
  return FootstepsRepository(
    db: ref.watch(appDatabaseProvider),
    countryResolver: ref.watch(countryResolverProvider),
  );
});

final healthStepsServiceProvider = Provider<HealthStepsService>((ref) => HealthStepsService());

final footstepsApiProvider = Provider<FootstepsApi>((ref) {
  return DioFootstepsApi(ref.watch(apiClientProvider));
});

Future<void> runFootstepsSync(WidgetRef ref) async {
  final repository = ref.read(footstepsRepositoryProvider);
  final health = ref.read(healthStepsServiceProvider);

  // Health Connect 미설치, 권한 거부, 지원하지 않는 기기 등 어떤 이유로든
  // 실패해도 조용히 넘어간다 — 걸음 수 동기화는 부가 기능이라 이것 때문에
  // 발걸음 탭 자체(체크인 서버 동기화)가 막히면 안 된다.
  try {
    await health.requestAuthorization();
    await syncStepsToDatabase(
      health: health,
      repository: repository,
      date: dayKeyOf(DateTime.now()),
    );
  } catch (_) {}

  return syncFootsteps(repository: repository, api: ref.read(footstepsApiProvider));
}
