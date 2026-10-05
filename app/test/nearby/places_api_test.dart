import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/nearby/api/places_api.dart';
import 'package:app/features/nearby/models/place.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Place.fromJson', () {
    test('서버 JSON을 파싱한다', () {
      final place = Place.fromJson(const {
        'id': 'p1',
        'name': '경복궁',
        'category': 'TOURIST',
        'address': '서울 종로구',
        'lat': 37.579,
        'lng': 126.977,
      });

      expect(place.id, 'p1');
      expect(place.name, '경복궁');
      expect(place.category, PlaceCategory.tourist);
      expect(place.address, '서울 종로구');
      expect(place.lat, 37.579);
      expect(place.lng, 126.977);
    });
  });

  group('fetchNearbyPlaces', () {
    test('lat/lng/category 쿼리로 GET /api/places/nearby를 호출해 파싱한다', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakePlacesAdapter();

      final places = await fetchNearbyPlaces(
        dio,
        lat: 37.5,
        lng: 127.0,
        category: PlaceCategory.restaurant,
      );

      expect(places, hasLength(1));
      expect(places.first.name, '맛집');
      expect(places.first.category, PlaceCategory.restaurant);
    });
  });
}

class _FakePlacesAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/places/nearby');
    expect(options.queryParameters['lat'], 37.5);
    expect(options.queryParameters['lng'], 127.0);
    expect(options.queryParameters['category'], 'RESTAURANT');

    final json = jsonEncode([
      {
        'id': 'p2',
        'name': '맛집',
        'category': 'RESTAURANT',
        'address': '서울 강남구',
        'lat': 37.5,
        'lng': 127.0,
      },
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
