import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x는 StateProvider를 legacy.dart로 분리했다(기본 barrel에서 제외됨).
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// 발걸음 기능의 로컬 국가 판정기를 재사용한다 — 외부 API 호출 없이 좌표만으로
// 즉시 국가를 판정해야 하고(주변정보 화면 진입마다 지오코딩 API를 부르면
// 느리고 오프라인에서 깨진다), 세계지도 GeoJSON도 이미 그쪽에서 로드해두므로
// 새로 파싱하지 않고 그대로 공유한다.
import '../../footsteps/data/checkin.dart';
import '../../footsteps/data/polygon_country_resolver.dart';
import '../../footsteps/providers/footsteps_providers.dart'
    show liveRouteProvider, overseasPositionProvider, worldCountryPolygonsProvider;
import '../location/location_repository.dart';
import '../models/place.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return GeolocatorLocationRepository();
});

final currentPositionProvider = FutureProvider((ref) {
  return ref.watch(locationRepositoryProvider).getCurrentPosition();
});

/// 주변 정보를 새로 조회하는 이동 기준 거리(m). Places 조회는 비용이 들어서 이 거리 이상
/// 움직였을 때만 기준 위치를 바꾼다.
const nearbyRefreshDistanceMeters = 300.0;

/// 주변 정보의 기준 위치. 해외 매핑 중이면 해외 현재 위치, 아니면 마지막 실제 GPS다.
/// 아직 위치가 하나도 없으면 null이고, 그때는 [nearbyPositionProvider]가 현재 위치를 읽는다.
final nearbyAnchorProvider = StateProvider<LatLng?>((ref) => null);

final _latestKnownPositionProvider = Provider<LatLng?>((ref) {
  final overseas = ref.watch(overseasPositionProvider);
  if (overseas != null) return overseas;
  final live = ref.watch(liveRouteProvider).asData?.value;
  return (live == null || live.isEmpty) ? null : live.last;
});

/// 앱이 켜져 있는 동안 기준 위치를 최신으로 유지한다 — 탭을 열어 두지 않아도 갱신된다.
/// 구독을 유지하려면 탭 화면 등에서 계속 listen/watch해야 한다.
final nearbyAnchorUpdaterProvider = Provider<void>((ref) {
  ref.listen<LatLng?>(
    _latestKnownPositionProvider,
    (_, next) {
      if (next == null) return;
      final current = ref.read(nearbyAnchorProvider);
      final moved = current == null
          ? double.infinity
          : Geolocator.distanceBetween(
              current.latitude, current.longitude, next.latitude, next.longitude);
      if (moved >= nearbyRefreshDistanceMeters) {
        ref.read(nearbyAnchorProvider.notifier).state = next;
      }
    },
    fireImmediately: true,
  );
});

/// 주변 정보 화면이 쓰는 현재 위치. 기준 위치가 있으면 그것을, 없으면 지금 GPS를 한 번 읽는다.
final nearbyPositionProvider = FutureProvider<LatLng>((ref) async {
  final anchor = ref.watch(nearbyAnchorProvider);
  if (anchor != null) return anchor;
  final position = await ref.watch(currentPositionProvider.future);
  return LatLng(position.latitude, position.longitude);
});

/// 위치 새로고침(주변 탭에 들어갈 때, 새로고침 버튼). 해외 매핑 중이면 해외 현재 위치로,
/// 아니면 실제 GPS를 새로 읽어 기준 위치로 삼는다.
Future<void> refreshNearbyPosition(WidgetRef ref) async {
  final overseas = ref.read(overseasPositionProvider);
  if (overseas != null) {
    ref.read(nearbyAnchorProvider.notifier).state = overseas;
    return;
  }
  final position = await ref.refresh(currentPositionProvider.future);
  ref.read(nearbyAnchorProvider.notifier).state = LatLng(position.latitude, position.longitude);
}

/// 현재 GPS 위치가 속한 국가(ISO2). 판정 실패(바다 위, GeoJSON 미로드 등)면 null.
final currentLocationCountryProvider = FutureProvider<String?>((ref) async {
  final position = await ref.watch(nearbyPositionProvider.future);
  final polygons = await ref.watch(worldCountryPolygonsProvider.future);
  final iso = await PolygonCountryResolver(polygons)
      .resolveIso2(position.latitude, position.longitude);
  return iso == Checkin.unknownCountry ? null : iso;
});

/// 현재 선택된 Places 필터 카테고리. 기본값은 관광지.
final nearbyCategoryProvider =
    StateProvider<PlaceCategory>((ref) => PlaceCategory.tourist);

/// 여행경보·재외공관 조회 대상 국가(ISO2). 사용자가 직접 고르기 전에는 null이며,
/// 화면에서는 null일 때 현재 위치가 속한 국가(currentLocationCountryProvider)를
/// 기본값으로 쓴다 — 그마저 판정되지 않았으면 국가 목록의 첫 항목으로 대체한다.
final selectedCountryProvider = StateProvider<String?>((ref) => null);

/// 드롭다운에 실제로 넣을 국가(ISO2)를 고른다.
///
/// `DropdownButton`은 value가 items 중 정확히 하나와 일치해야 하고, 아니면 assertion으로
/// 터진다. 현재 위치 국가는 목록(Tier A)에 없을 수 있다 — 한국에서 열면 KR이 그렇다 —
/// 그래서 선택값·위치값 모두 목록에 있는지 확인한 뒤에만 쓴다.
String? effectiveCountryIso2({
  required String? selected,
  required String? currentLocation,
  required List<String> available,
}) {
  bool isAvailable(String? iso) => iso != null && available.contains(iso);

  if (isAvailable(selected)) return selected;
  if (isAvailable(currentLocation)) return currentLocation;
  return available.isEmpty ? null : available.first;
}
