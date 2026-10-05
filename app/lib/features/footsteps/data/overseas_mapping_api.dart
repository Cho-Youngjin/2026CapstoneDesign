import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 해외 매핑 테스트/기능 전용 서버 호출. 도로 스냅(route_snapping_api.dart)과
/// 별개로, 국내 이동을 해외 도로망 위에서의 걸음으로 옮기는 서버 로직(mock_server.py의
/// walk_overseas_segment)을 부른다. 설계 문서:
/// docs/superpowers/specs/2026-09-29-overseas-footsteps-route-projection.md

/// 사용자가 고른 해외 출발 좌표(anchor)가 도로 근처인지 검증하고, 통과하면 도로
/// 위로 붙인 좌표를 돌려준다(도로에서 벗어났으면 null).
Future<LatLng?> validateOverseasAnchor(Dio dio, String country, LatLng point) async {
  final response = await dio.post<Map<String, dynamic>>(
    '/api/route/overseas-anchor/validate',
    data: {'country': country, 'lat': point.latitude, 'lng': point.longitude},
  );
  final data = response.data;
  final snapped = data?['snapped'] as Map<String, dynamic>?;
  if (data?['ok'] != true || snapped == null) return null;
  return LatLng((snapped['lat'] as num).toDouble(), (snapped['lng'] as num).toDouble());
}

class OverseasWalkResult {
  const OverseasWalkResult({
    required this.ok,
    required this.matched,
    this.newAnchor,
    this.state,
  });

  const OverseasWalkResult.failed() : this(ok: false, matched: const []);

  final bool ok;
  final List<LatLng> matched;
  final LatLng? newAnchor;

  /// 서버가 다음 요청에서 그대로 돌려받길 원하는 값(진행 방향·지나온 길 등). 앱은 내용을
  /// 해석하지 않고 들고만 있다가 다음 요청에 실어 보낸다.
  final Map<String, dynamic>? state;
}

/// anchor(도로 위 점)에서 국내 이동 거리(krPoints, 첫 원소는 직전 요청의 마지막 국내
/// 좌표)만큼 해외 도로를 따라 걸은 결과를 받는다. 결과 경로와 newAnchor는 항상 도로
/// 위이며, 막다른 길 등은 서버가 되돌아가는 경로로 처리한다.
Future<OverseasWalkResult> walkOverseasSegment(
  Dio dio, {
  required String country,
  required LatLng anchor,
  required List<LatLng> krPoints,
  Map<String, dynamic>? state,
}) async {
  final response = await dio.post<Map<String, dynamic>>(
    '/api/route/overseas-walk',
    data: {
      'country': country,
      'anchor': {'lat': anchor.latitude, 'lng': anchor.longitude},
      'points': [for (final p in krPoints) {'lat': p.latitude, 'lng': p.longitude}],
      'state': state,
    },
  );

  final data = response.data ?? const {};
  if (data['ok'] != true) return const OverseasWalkResult.failed();

  final matched = (data['matched'] as List<dynamic>? ?? const [])
      .map((e) => e as Map<String, dynamic>)
      .map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
      .toList();

  final newAnchorRaw = data['newAnchor'] as Map<String, dynamic>?;
  final newAnchor = newAnchorRaw == null
      ? null
      : LatLng((newAnchorRaw['lat'] as num).toDouble(), (newAnchorRaw['lng'] as num).toDouble());

  return OverseasWalkResult(
    ok: true,
    matched: matched,
    newAnchor: newAnchor,
    state: data['state'] as Map<String, dynamic>?,
  );
}
