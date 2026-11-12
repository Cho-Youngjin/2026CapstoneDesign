import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 위치 스트림을 받아 화면에 바로 이어 그릴 수 있도록 지금까지 지나온 좌표를 그대로 누적해 낸다.
/// 반환하는 좌표 목록은 이번 스트림 구독 동안만 유효한 화면 표시용 캐시다.
///
/// 저장은 하지 않는다(설계 2026-11-07 9-2). 예전에는 앱이 켜져 있을 때마다 모든 좌표를 RoutePoints에 남겼지만,
/// 이제 이동 기록은 여행 기간에만 기록 서비스가 제안 정책으로 남긴다(trip/trip_recorder.dart).
///
/// 촘촘한 distanceFilter로 구독해야 걷는 경로가 자연스럽게 이어진다. 국가 판정(체크인)은 이 스트림과 무관하게
/// WorkManager 1시간 주기(여행 기간에만)와 수동 "여기 저장"만 담당한다.
Stream<List<LatLng>> trackLiveRoute(Stream<Position> positions, {int maxPoints = 2000}) async* {
  final points = <LatLng>[];
  await for (final position in positions) {
    points.add(LatLng(position.latitude, position.longitude));
    while (points.length > maxPoints) {
      points.removeAt(0);
    }
    yield List.unmodifiable(points);
  }
}
