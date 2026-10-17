import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/footsteps_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('체크인 recordedAt은 로컬 시각이어도 서버가 받는 UTC(Z 포함) 문자열로 보낸다', () async {
    final adapter = _CapturingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;

    // drift는 DateTime을 로컬(UTC가 아닌) 값으로 돌려준다 — toIso8601String()에 Z가 안 붙는다.
    final local = DateTime(2026, 10, 17, 13, 2, 19);
    await DioFootstepsApi(dio).pushCheckins([
      Checkin(
        id: 1,
        lat: 37.5,
        lng: 127.0,
        countryIso: 'KR',
        recordedAt: local,
        source: CheckinSource.auto,
        synced: false,
      ),
    ]);

    final sent = adapter.body.single as Map<String, dynamic>;
    expect(sent['recordedAt'], local.toUtc().toIso8601String());
    expect(sent['recordedAt'], endsWith('Z'));
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  late List<dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    body = options.data as List<dynamic>;
    return ResponseBody.fromString(
      jsonEncode([
        {'localId': 1, 'serverId': 'srv-1'},
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
