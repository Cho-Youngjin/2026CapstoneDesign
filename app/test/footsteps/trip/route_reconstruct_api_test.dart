import 'dart:convert';

import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/trip/route_reconstruct_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;

import '../../support/stub_http_client_adapter.dart';

RoutePoint point(int second, {int? steps, String? state}) => RoutePoint(
      lat: 37.5 + second / 100000,
      lng: 127.0,
      countryIso: 'KR',
      recordedAt: DateTime.fromMillisecondsSinceEpoch(1792400000000 + second * 1000),
      tripId: 7,
      accuracyM: 8,
      stepsSincePrev: steps,
      state: state,
    );

Stay stay(int fromSecond, int toSecond) => Stay(
      arriveMs: 1792400000000 + fromSecond * 1000,
      leaveMs: 1792400000000 + toSecond * 1000,
      lat: 37.6,
      lng: 127.1,
      nPoints: 3,
    );

void main() {
  test('점·머문 곳을 복원 API 계약대로 보내고(방법은 서버 기본값) 구간을 받는다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = StubHttpClientAdapter(
      path: '/api/route/reconstruct',
      statusCode: 200,
      body: jsonEncode({
        'method': 'osrm_match_radius',
        'segments': [
          {
            'kind': 'walk',
            'coords': [
              {'lat': 37.5, 'lng': 127.0},
              {'lat': 37.51, 'lng': 127.01},
            ],
            'fallback': false,
          },
          {
            'kind': 'estimated',
            'coords': [
              {'lat': 37.51, 'lng': 127.01},
              {'lat': 37.6, 'lng': 127.1},
            ],
            'fallback': true,
          },
        ],
      }),
    );
    dio.httpClientAdapter = adapter;

    final segments = await RouteReconstructApi(dio)
        .reconstruct([point(0, state: 'unknown'), point(60, steps: 64, state: 'walking')], [stay(30, 40)]);

    final sent = adapter.lastRequest!.data as Map<String, dynamic>;
    expect(sent.containsKey('method'), isFalse);
    expect(sent['points'], [
      {'t': 1792400000000, 'lat': 37.5, 'lng': 127.0, 'accuracy': 8.0, 'stepsSincePrev': null, 'state': 'unknown'},
      {'t': 1792400060000, 'lat': 37.5006, 'lng': 127.0, 'accuracy': 8.0, 'stepsSincePrev': 64, 'state': 'walking'},
    ]);
    expect(sent['stays'], [
      {'arrive': 1792400030000, 'leave': 1792400040000, 'lat': 37.6, 'lng': 127.1},
    ]);
    expect(segments.map((s) => (s.kind, s.coords.length, s.fallback)), [('walk', 2, false), ('estimated', 2, true)]);
  });

  test('서버 상한을 넘는 날은 마지막 점을 겹쳐 나누고, 머문 곳은 그 조각과 겹치는 것만 넣는다', () {
    final points = [for (var s = 0; s < 5; s++) point(s * 100)];
    final stays = [stay(50, 80), stay(250, 350), stay(420, 430)];

    final chunks = reconstructChunks(points, stays, maxPoints: 3);

    expect(chunks.map((c) => c.points.map((p) => p.recordedAt.millisecondsSinceEpoch ~/ 1000 - 1792400000)), [
      [0, 100, 200],
      [200, 300, 400],
    ]);
    expect(chunks[0].stays.map((s) => s.arriveMs ~/ 1000 - 1792400000), [50]);
    expect(chunks[1].stays.map((s) => s.arriveMs ~/ 1000 - 1792400000), [250]);
    expect(reconstructChunks(const [], stays), isEmpty);
    expect(reconstructChunks(points, stays), hasLength(1));
  });
}
