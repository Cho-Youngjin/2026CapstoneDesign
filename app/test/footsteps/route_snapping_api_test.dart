import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/footsteps/data/route_snapping_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('좌표가 2개 미만이면 서버를 부르지 않고 그대로 돌려준다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FailingAdapter();

    final result = await snapToRoads(dio, const [LatLng(37.5, 127.0)]);

    expect(result, const [LatLng(37.5, 127.0)]);
  });

  test('서버가 스냅된 좌표를 응답하면 그대로 파싱해 돌려준다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeSnapAdapter();

    final result = await snapToRoads(dio, const [
      LatLng(37.5, 127.0),
      LatLng(37.501, 127.001),
    ]);

    expect(result, const [
      LatLng(37.5001, 127.0001),
      LatLng(37.5011, 127.0011),
    ]);
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw StateError('호출되면 안 됨');
  }

  @override
  void close({bool force = false}) {}
}

class _FakeSnapAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/route/snap');

    final json = jsonEncode([
      {'lat': 37.5001, 'lng': 127.0001},
      {'lat': 37.5011, 'lng': 127.0011},
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
