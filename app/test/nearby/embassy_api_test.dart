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

  // 서버 스키마(V3__travel_alert_embassy.sql)는 phone/emergency_phone/address를
  // nullable로 선언한다. 공공데이터에 전화번호가 빈 분관이 섞여 있으면 예전 코드는
  // `as String` 캐스팅에서 던져버려 공관 목록 전체가 사라졌다.
  test('전화번호·주소가 비어 있는 공관도 목록에서 빠지지 않는다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _NullFieldEmbassyAdapter();

    final embassies = await fetchEmbassies(dio, iso2: 'VN');

    expect(embassies, hasLength(2));
    expect(embassies.first.phone, isNull);
    expect(embassies.first.emergencyPhone, isNull);
    expect(embassies.first.address, isNull);
    expect(embassies.last.phone, '+84-24-xxx-xxxx');
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

class _NullFieldEmbassyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final json = jsonEncode([
      {
        'id': 2,
        'type': '분관',
        'name': '주호치민분관',
        'lat': 10.78,
        'lng': 106.70,
        'phone': null,
        'emergencyPhone': null,
        'address': null,
      },
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
