import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/checkin.dart';
import '../data/country_resolver.dart';
import '../data/footsteps_repository.dart';

/// 위치 스트림을 받아 좌표를 국가와 함께 영구 저장하면서(RoutePoints 테이블),
/// 화면에 바로 이어 그릴 수 있도록 지금까지 지나온 좌표를 그대로 누적해 낸다.
/// 저장은 앱을 껐다 켜거나 다른 화면에 갔다 와도 남는 영구 기록이고, 반환하는
/// 좌표 목록은 이번 스트림 구독 동안만 유효한 화면 표시용 캐시다.
///
/// 촘촘한 distanceFilter로 구독해야 걷는 경로가 자연스럽게 이어진다. 미확인(XX)
/// 좌표는 저장하지 않지만(국가 없는 기록은 나중에 조회할 방법이 없어 의미가 없다)
/// 화면 표시용 경로에는 그대로 포함해 선이 끊겨 보이지 않게 한다.
///
/// 국가 판정(체크인)은 이 스트림과 무관하게 WorkManager 1시간 주기와 수동
/// "여기 저장"만 담당한다 — 여기서는 오직 이동 경로 표시·영구 기록만 한다.
Stream<List<LatLng>> trackAndPersistLiveRoute({
  required Stream<Position> positions,
  required CountryResolver countryResolver,
  required FootstepsRepository repository,
  int maxPoints = 2000,
}) async* {
  final points = <LatLng>[];
  await for (final position in positions) {
    final iso = await countryResolver.resolveIso2(position.latitude, position.longitude);
    if (iso != Checkin.unknownCountry) {
      await repository.recordRoutePoint(
        position.latitude,
        position.longitude,
        iso,
        DateTime.now().toUtc(),
      );
    }

    points.add(LatLng(position.latitude, position.longitude));
    while (points.length > maxPoints) {
      points.removeAt(0);
    }
    yield List.unmodifiable(points);
  }
}
