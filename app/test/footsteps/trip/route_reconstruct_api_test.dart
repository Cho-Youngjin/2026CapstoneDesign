import 'dart:convert';

import 'package:app/features/footsteps/data/route_point.dart';
import 'package:app/features/footsteps/trip/route_reconstruct_api.dart';
import 'dart:typed_data';

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

/// 요청마다 미리 정한 응답을 차례로 돌려주는 어댑터. 받은 요청을 모두 기록한다.
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.bodies);

  final List<Map<String, dynamic>> bodies;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = bodies[requests.length];
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> walkBody(List<List<double>> coords, {bool fallback = false}) => {
      'method': 'osrm_match_radius',
      'segments': [
        {
          'kind': 'walk',
          'coords': [for (final c in coords) {'lat': c[0], 'lng': c[1]}],
          'fallback': fallback,
        },
      ],
    };

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

  test('복원 요청만 받기 제한 시간을 60초로 늘린다(OSRM 매칭·경로가 긴 날은 10초를 넘길 수 있다)', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test', receiveTimeout: const Duration(seconds: 10)));
    final adapter = _SequenceAdapter([walkBody([[37.5, 127.0], [37.51, 127.0]])]);
    dio.httpClientAdapter = adapter;

    await RouteReconstructApi(dio).reconstruct([point(0), point(60)], const []);

    expect(adapter.requests.single.receiveTimeout, const Duration(seconds: 60));
    expect(dio.options.receiveTimeout, const Duration(seconds: 10)); // 공용 클라이언트 설정은 그대로
  });

  test('여러 조각으로 나눠 보내면 조각 경계에서 끝점이 서로 다를 때 앞 조각의 끝을 뒷 조각 앞에 붙여 잇는다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    // 조각 1의 끝 (37.5010)과 조각 2의 시작 (37.5015)은 약 55m 벌어져 있다(겹친 점을 다른 문맥에서 매칭).
    final adapter = _SequenceAdapter([
      walkBody([[37.5000, 127.0], [37.5010, 127.0]]),
      walkBody([[37.5015, 127.0], [37.5030, 127.0]]),
    ]);
    dio.httpClientAdapter = adapter;

    final segments = await RouteReconstructApi(dio, maxPoints: 3).reconstruct([for (var s = 0; s < 5; s++) point(s * 100)], const []);

    expect(adapter.requests, hasLength(2));
    expect((adapter.requests[0].data as Map)['points'], hasLength(3));
    expect((adapter.requests[1].data as Map)['points'], hasLength(3));
    expect(segments, hasLength(2));
    expect(segments[0].coords.map((c) => c.latitude), [37.5000, 37.5010]);
    expect(segments[1].coords.map((c) => c.latitude), [37.5010, 37.5015, 37.5030]);
  });

  test('조각 경계의 끝점이 0.5m 안으로 같으면 덧붙이지 않고, 종류·fallback 표시도 바꾸지 않는다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    final adapter = _SequenceAdapter([
      walkBody([[37.5000, 127.0], [37.5010, 127.0]]),
      walkBody([[37.5010, 127.0], [37.5030, 127.0]], fallback: true),
    ]);
    dio.httpClientAdapter = adapter;

    final segments = await RouteReconstructApi(dio, maxPoints: 3).reconstruct([for (var s = 0; s < 5; s++) point(s * 100)], const []);

    expect(segments[1].coords.map((c) => c.latitude), [37.5010, 37.5030]);
    expect(segments[1].fallback, isTrue);
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
