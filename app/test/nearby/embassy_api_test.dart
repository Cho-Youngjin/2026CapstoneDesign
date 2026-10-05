import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/nearby/api/embassy_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GET /api/countries/{iso2}/embassies 를 호출해 파싱한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeEmbassyAdapter();

    final embassies = await fetchEmbassies(dio, iso2: 'VN');

    expect(embassies, hasLength(1));
    expect(embassies.first.name, '주베트남대한민국대사관');
    expect(embassies.first.emergencyPhone, '+84-90-xxx-xxxx');
  });
}

class _FakeEmbassyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/countries/VN/embassies');
    final json = jsonEncode([
      {
        'id': 1,
        'type': '대사관',
        'name': '주베트남대한민국대사관',
        'lat': 21.02,
        'lng': 105.83,
        'phone': '+84-24-xxx-xxxx',
        'emergencyPhone': '+84-90-xxx-xxxx',
        'address': '하노이',
      },
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
