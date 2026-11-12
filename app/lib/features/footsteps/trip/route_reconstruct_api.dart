import 'package:dio/dio.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/route_point.dart';

/// 복원한 경로의 구간 하나(서버 `route/RouteSegment.java`). [kind]는 `walk`·`vehicle`·`estimated`다.
/// [fallback]이면 OSRM이 없거나 매칭에 실패해 직선으로 대신 채운 구간이다.
class RouteSegmentView {
  const RouteSegmentView({required this.kind, required this.coords, required this.fallback});

  /// 복원 API의 구간 종류. `estimated`는 GPS가 없던 10분 이상의 공백(지하철 등)을 최단경로로 이은 것이라 점선으로 그린다.
  static const walk = 'walk';
  static const vehicle = 'vehicle';
  static const estimated = 'estimated';

  final String kind;
  final List<LatLng> coords;
  final bool fallback;

  factory RouteSegmentView.fromJson(Map<String, dynamic> json) => RouteSegmentView(
        kind: json['kind'] as String,
        coords: [
          for (final c in json['coords'] as List)
            LatLng(((c as Map)['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
        ],
        fallback: json['fallback'] as bool? ?? false,
      );
}

/// 한 번에 보낼 점·머문 곳. 서버가 점 2000개, 머문 곳 500개까지 받는다(설계 6-1).
class ReconstructChunk {
  const ReconstructChunk(this.points, this.stays);

  final List<RoutePoint> points;
  final List<Stay> stays;
}

/// 하루치 점이 서버 상한([maxPoints])을 넘으면(탈것을 오래 타 5초마다 잰 날) 나눠 보낸다. 앞 조각의 마지막 점을 다음 조각의
/// 첫 점으로 겹쳐 구간이 끊기지 않게 하고, 머문 곳은 그 조각의 시간 범위와 겹치는 것만 넣는다 — 서버는 범위 밖의 머문 곳도
/// 중심점을 끼워 넣기 때문이다.
List<ReconstructChunk> reconstructChunks(List<RoutePoint> points, List<Stay> stays, {int maxPoints = 2000}) {
  if (points.isEmpty) return const [];
  final chunks = <ReconstructChunk>[];
  var start = 0;
  while (true) {
    final end = (start + maxPoints).clamp(0, points.length);
    final part = points.sublist(start, end);
    final from = part.first.recordedAt.millisecondsSinceEpoch;
    final to = part.last.recordedAt.millisecondsSinceEpoch;
    chunks.add(ReconstructChunk(part, [
      for (final s in stays)
        if (s.leaveMs >= from && s.arriveMs <= to) s,
    ]));
    if (end >= points.length) return chunks;
    start = end - 1;
  }
}

/// `POST /api/route/reconstruct`(R5)의 앱 쪽 클라이언트. 방법은 보내지 않아 서버 기본값(`osrm_match_radius`)을 쓴다(설계 9-4).
/// 기록 좌표는 복원할 때만 보내고 서버는 저장하지 않는다(설계 9-3). 실패하면 dio의 [DioException]을 그대로 던진다.
class RouteReconstructApi {
  RouteReconstructApi(this._dio);

  final Dio _dio;

  Future<List<RouteSegmentView>> reconstruct(List<RoutePoint> points, List<Stay> stays) async {
    final segments = <RouteSegmentView>[];
    for (final chunk in reconstructChunks(points, stays)) {
      final response = await _dio.post<Map<String, dynamic>>('/api/route/reconstruct', data: {
        'points': [
          for (final p in chunk.points)
            {
              't': p.recordedAt.millisecondsSinceEpoch,
              'lat': p.lat,
              'lng': p.lng,
              'accuracy': p.accuracyM,
              'stepsSincePrev': p.stepsSincePrev,
              'state': p.state,
            },
        ],
        'stays': [
          for (final s in chunk.stays) {'arrive': s.arriveMs, 'leave': s.leaveMs, 'lat': s.lat, 'lng': s.lng},
        ],
      });
      segments.addAll([
        for (final s in response.data!['segments'] as List) RouteSegmentView.fromJson(s as Map<String, dynamic>),
      ]);
    }
    return segments;
  }
}
