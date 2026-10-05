import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 서버(Google Roads API 프록시)에 좌표를 보내 실제 도로 위로 스냅한 좌표를
/// 받는다. 서버가 스냅에 실패하면(포인트 간격이 너무 넓음, 키 없음 등) 받은
/// 좌표를 그대로 돌려주므로, 이 함수는 항상 원본과 같거나 더 촘촘한 좌표
/// 목록을 반환한다 — 별도의 실패 분기가 필요 없다.
Future<List<LatLng>> snapToRoads(Dio dio, List<LatLng> points) async {
  if (points.length < 2) return points;

  final response = await dio.post<List<dynamic>>(
    '/api/route/snap',
    data: [for (final p in points) {'lat': p.latitude, 'lng': p.longitude}],
  );

  return response.data!
      .map((e) => e as Map<String, dynamic>)
      .map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
      .toList();
}
