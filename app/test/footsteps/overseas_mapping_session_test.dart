import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/db/app_database.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:app/features/footsteps/map/world_map_page.dart' show visitedCountriesProvider;
import 'package:app/features/footsteps/providers/footsteps_providers.dart';
import 'package:app/features/footsteps/providers/overseas_mapping_session.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _FixedCountryResolver implements CountryResolver {
  const _FixedCountryResolver(this.iso);
  final String iso;

  @override
  Future<String> resolveIso2(double lat, double lng) async => iso;
}

Position _positionAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// /api/route/overseas-walk에 정해 둔 해외 경로를 응답하고, 받은 요청 본문을 기록한다.
class _FakeWalkAdapter implements HttpClientAdapter {
  final requests = <Map<String, dynamic>>[];

  /// 설정하면 응답을 이 completer가 끝날 때까지 붙잡아 둔다(느린 네트워크 흉내).
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/route/overseas-walk');
    requests.add(options.data as Map<String, dynamic>);
    final hold = gate;
    if (hold != null) await hold.future;

    final json = jsonEncode({
      'ok': true,
      'matched': [
        {'lat': 35.6800, 'lng': 139.7600}, // 직전 anchor와 같은 점(저장에서 중복 제외)
        {'lat': 35.6810, 'lng': 139.7610},
        {'lat': 35.6820, 'lng': 139.7620},
      ],
      'newAnchor': {'lat': 35.6820, 'lng': 139.7620},
      'state': {'heading': 45.0},
    });
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late StreamController<Position> gps;
  late _FakeWalkAdapter adapter;
  late ProviderContainer container;

  const anchor = LatLng(35.6800, 139.7600);

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gps = StreamController<Position>.broadcast();
    adapter = _FakeWalkAdapter();
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter),
      footstepsRepositoryProvider.overrideWithValue(
        FootstepsRepository(db: db, countryResolver: const _FixedCountryResolver('JP')),
      ),
      overseasMappingPositionStreamProvider.overrideWithValue(gps.stream),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await gps.close();
    await db.close();
  });

  test('시작하면 해외 매핑 중 상태가 켜지고 해외 현재 위치가 출발점이 된다', () {
    container.read(overseasMappingProvider.notifier).start('JP', anchor);

    final state = container.read(overseasMappingProvider);
    expect(state.active, isTrue);
    expect(state.country, 'JP');
    expect(state.anchor, anchor);
    expect(container.read(overseasMappingActiveProvider), isTrue);
    expect(container.read(overseasPositionProvider), anchor);
  });

  test('이동이 기준 거리를 넘으면 해외 경로를 받아 이어 붙이고 JP로 저장한다', () async {
    container.read(overseasMappingProvider.notifier).start('JP', anchor);

    gps.add(_positionAt(37.5000, 127.0000));
    // 위도 0.001° ≈ 111m — 기준(50m)을 넘는다.
    gps.add(_positionAt(37.5010, 127.0000));
    await settle();

    final state = container.read(overseasMappingProvider);
    expect(adapter.requests, hasLength(1));
    expect(state.anchor, const LatLng(35.6820, 139.7620));
    expect(state.jpRoute.last, const LatLng(35.6820, 139.7620));
    expect(state.krRoute, hasLength(2));
    // 해외 현재 위치도 주변 정보가 읽을 수 있게 갱신된다.
    expect(container.read(overseasPositionProvider), const LatLng(35.6820, 139.7620));

    // 직전 anchor와 같은 첫 점은 빼고 2개만 저장된다.
    final saved = await db.routePointsForCountry('JP');
    expect(saved.map((p) => (p.lat, p.lng)), [(35.6810, 139.7610), (35.6820, 139.7620)]);
  });

  test('시작과 멈춤 때 해외 체크인을 남겨 방문 국가와 이동 기록 목록에 나타나게 한다', () async {
    final notifier = container.read(overseasMappingProvider.notifier);
    notifier.start('JP', anchor);
    await settle();

    var checkins = await db.allCheckins();
    expect(checkins, hasLength(1));
    expect(checkins.single.countryIso, 'JP');
    expect((checkins.single.lat, checkins.single.lng), (anchor.latitude, anchor.longitude));

    // 걸어서 해외 현재 위치가 옮겨진 뒤 멈추면, 마지막 해외 위치로 한 번 더 남긴다.
    gps.add(_positionAt(37.5000, 127.0000));
    gps.add(_positionAt(37.5010, 127.0000));
    await settle();
    notifier.stop();
    await settle();

    checkins = await db.allCheckins();
    expect(checkins, hasLength(2));
    expect(checkins.map((c) => c.countryIso), ['JP', 'JP']);
    expect((checkins.last.lat, checkins.last.lng), (35.6820, 139.7620));
  });

  test('기준 거리보다 적게 움직이면 서버를 부르지 않는다', () async {
    container.read(overseasMappingProvider.notifier).start('JP', anchor);

    gps.add(_positionAt(37.5000, 127.0000));
    gps.add(_positionAt(37.5002, 127.0000)); // ≈ 22m
    await settle();

    expect(adapter.requests, isEmpty);
  });

  test('멈추면 상태가 꺼지고 더 이상 위치를 받지 않는다', () async {
    final notifier = container.read(overseasMappingProvider.notifier);
    notifier.start('JP', anchor);

    notifier.stop();
    await settle();

    expect(container.read(overseasMappingProvider).active, isFalse);
    expect(container.read(overseasMappingActiveProvider), isFalse);
    expect(container.read(overseasPositionProvider), isNull);
    expect(gps.hasListener, isFalse);
  });

  List<(double, double)> sentPoints(Map<String, dynamic> request) => [
        for (final p in request['points'] as List<dynamic>)
          ((p as Map<String, dynamic>)['lat'] as double, p['lng'] as double),
      ];

  test('요청을 기다리는 동안 들어온 좌표는 버리지 않고 다음 구간에 넣는다', () async {
    container.read(overseasMappingProvider.notifier).start('JP', anchor);
    adapter.gate = Completer<void>();

    gps.add(_positionAt(37.5000, 127.0000));
    gps.add(_positionAt(37.5010, 127.0000)); // 첫 요청 시작(응답 대기)
    await settle();
    gps.add(_positionAt(37.5020, 127.0000)); // 요청 중에 들어온 좌표
    await settle();
    adapter.gate!.complete();
    adapter.gate = null;
    await settle();

    gps.add(_positionAt(37.5030, 127.0000)); // 다음 요청
    await settle();

    expect(adapter.requests, hasLength(2));
    expect(sentPoints(adapter.requests[1]), [(37.5010, 127.0), (37.5020, 127.0), (37.5030, 127.0)]);
  });

  test('요청을 기다리는 중에 멈추면 그 구간까지 저장하고 마지막 해외 위치로 체크인한다', () async {
    final notifier = container.read(overseasMappingProvider.notifier);
    notifier.start('JP', anchor);
    adapter.gate = Completer<void>();

    gps.add(_positionAt(37.5000, 127.0000));
    gps.add(_positionAt(37.5010, 127.0000));
    await settle();
    final stopping = notifier.stop();
    adapter.gate!.complete();
    await stopping;
    await settle();

    final saved = await db.routePointsForCountry('JP');
    expect(saved.map((p) => (p.lat, p.lng)), [(35.6810, 139.7610), (35.6820, 139.7620)]);
    final checkins = await db.allCheckins();
    expect((checkins.last.lat, checkins.last.lng), (35.6820, 139.7620));
    expect(container.read(overseasMappingProvider).active, isFalse);
  });

  test('멈추면 세계지도의 방문 국가 목록을 다시 읽어 새로 간 나라가 바로 보인다', () async {
    // 세계지도가 한 번 읽어 캐시해 둔 상태(아직 아무 데도 안 감)
    expect(await container.read(visitedCountriesProvider.future), isEmpty);

    final notifier = container.read(overseasMappingProvider.notifier);
    notifier.start('JP', anchor);
    await settle();
    await notifier.stop();
    await settle();

    expect(await container.read(visitedCountriesProvider.future), {'JP'});
  });
}
