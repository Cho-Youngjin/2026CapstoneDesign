import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x는 StateProvider를 legacy.dart로 분리했다(기본 barrel에서 제외됨).
import 'package:flutter_riverpod/legacy.dart';

// 발걸음 기능의 로컬 국가 판정기를 재사용한다 — 외부 API 호출 없이 좌표만으로
// 즉시 국가를 판정해야 하고(주변정보 화면 진입마다 지오코딩 API를 부르면
// 느리고 오프라인에서 깨진다), 세계지도 GeoJSON도 이미 그쪽에서 로드해두므로
// 새로 파싱하지 않고 그대로 공유한다.
import '../../footsteps/data/checkin.dart';
import '../../footsteps/data/polygon_country_resolver.dart';
import '../../footsteps/providers/footsteps_providers.dart' show worldCountryPolygonsProvider;
import '../location/location_repository.dart';
import '../models/place.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return GeolocatorLocationRepository();
});

final currentPositionProvider = FutureProvider((ref) {
  return ref.watch(locationRepositoryProvider).getCurrentPosition();
});

/// 현재 GPS 위치가 속한 국가(ISO2). 판정 실패(바다 위, GeoJSON 미로드 등)면 null.
final currentLocationCountryProvider = FutureProvider<String?>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
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
