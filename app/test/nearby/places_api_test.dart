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

    test('응답 순서와 관계없이 현재 위치에서 가까운 순으로 정렬한다', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _UnorderedPlacesAdapter();

      final places = await fetchNearbyPlaces(
        dio,
        lat: 35.6812,
        lng: 139.7671,
        category: PlaceCategory.tourist,
      );

      // 서버는 먼 곳(황궁 북쪽 공원) → 가까운 곳(도쿄역) → 중간(긴자) 순으로 돌려준다.
      expect(places.map((p) => p.id), ['near', 'mid', 'far']);
    });
  });
}

class _UnorderedPlacesAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Map<String, Object> place(String id, double lat, double lng) => {
          'id': id,
          'name': id,
          'category': 'TOURIST',
          'address': '도쿄',
          'lat': lat,
          'lng': lng,
        };
    final json = jsonEncode([
      place('far', 35.7148, 139.7967), // 센소지 방면, 약 4km
      place('near', 35.6815, 139.7675), // 도쿄역 바로 옆
      place('mid', 35.6717, 139.7649), // 긴자 방면, 약 1km
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
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
