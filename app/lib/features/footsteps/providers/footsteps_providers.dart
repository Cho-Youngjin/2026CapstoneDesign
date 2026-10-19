import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x는 StateProvider를 legacy.dart로 분리했다(기본 barrel에서 제외됨).
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/db/app_database.dart';
import '../../../core/network/api_client.dart';
import '../data/checkin.dart';
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

/// 실시간 추적 스위치. 앱이 백그라운드로 가면 탭 셸(router.dart의 _TabScaffold)이 false로 내려
/// GPS 스트림을 끊는다(배터리 방어) — 다시 true가 되면 autoDispose provider가 재빌드되며 스트림을 새로 연다.
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
/// 해외 매핑이 진행 중인지. 진행 중에는 한국에서의 실제 이동을 RoutePoints에 저장하지
/// 않는다(해외 매핑 화면이 대신 해외 경로를 저장한다).
final overseasMappingActiveProvider = StateProvider<bool>((ref) => false);

/// 해외 매핑 중 투영된 해외 현재 위치(도로 위). 해외 매핑이 아닐 때는 null이다.
/// 주변 정보가 "지금 있는 곳"을 해외 위치로 삼는 데 쓴다.
final overseasPositionProvider = StateProvider<LatLng?>((ref) => null);

/// 실시간 경로용 위치 스트림을 여는 함수. 테스트에서 실제 GPS 대신 가짜 스트림을 넣으려고 분리했다.
final livePositionsProvider = Provider<Stream<Position> Function()>(
  (ref) => () => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ),
);

final liveRouteProvider = StreamProvider.autoDispose<List<LatLng>>((ref) {
  final enabled = ref.watch(realtimeTrackingEnabledProvider);
  if (!enabled) return const Stream.empty();

  final positions = ref.watch(livePositionsProvider)();

  return trackAndPersistLiveRoute(
    positions: positions,
    countryResolver: ref.watch(realtimeCountryResolverProvider),
    repository: ref.watch(footstepsRepositoryProvider),
    // 국가 판정을 기다리는 사이 추적이 꺼지거나(백그라운드 전환) 화면을 떠나 이 provider가 사라졌으면
    // ref를 쓸 수 없다. 그때 들어온 좌표는 저장하지 않는다 — 구독이 이미 끝난 뒤의 마지막 한 점이다.
    shouldPersist: () => ref.mounted && !ref.read(overseasMappingActiveProvider),
  );
});

/// 앱 전체 위치 스트림의 최신 좌표가 속한 국가(ISO2). 아직 위치가 없거나 판정할 수 없으면 null.
/// 국가 상세 화면이 "지금 실제로 있는 나라"인지 가를 때 쓴다.
final liveCountryProvider = FutureProvider.autoDispose<String?>((ref) async {
  final live = ref.watch(liveRouteProvider).asData?.value;
  if (live == null || live.isEmpty) return null;
  final iso = await ref
      .watch(realtimeCountryResolverProvider)
      .resolveIso2(live.last.latitude, live.last.longitude);
  return iso == Checkin.unknownCountry ? null : iso;
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
