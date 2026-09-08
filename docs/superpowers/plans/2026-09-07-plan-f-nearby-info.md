# Plan F — 앱: 주변 여행 정보 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `NearbyPage`('주변' 탭)에 실제 화면을 채운다. 현재 위치 기준 Places 검색(관광지·음식점·약국·ATM 필터), 지도+리스트 동시 표시, 선택한 국가의 외교부 여행경보 배지, 재외공관 연락처 카드를 한 화면에 통합한다.

**Architecture:** `NearbyPage`는 4개의 독립된 데이터 소스(현재 위치, Places, 여행경보, 재외공관)를 Riverpod provider로 각각 로드하고 하나의 스크롤 화면에 조립한다. 서버 호출은 전부 Phase 0 Task 9가 만든 `apiClientProvider`(dio, 토큰 인터셉터 포함)를 재사용하며 개별 API 파일은 `country_api.dart`와 동일한 패턴(모델 + `fromJson` + `FutureProvider`)을 따른다. 지도는 Plan C가 만드는 지도 위젯을 재사용하는 것이 이상적이지만, 이 계획서 작성 시점에 Plan C의 지도 위젯이 재사용 가능한 형태(별도 컴포넌트로 추출)로 나올지 확정되지 않았으므로 **Task 3에서 이 화면 전용의 최소 `NearbyMapView`를 자체 구현**한다. `google_maps_flutter`의 `GoogleMap` 위젯을 직접 감싸는 20줄 내외의 얇은 래퍼이므로, Plan C 쪽에 공용 지도 컴포넌트가 이미 나와 있다면 그것으로 교체하는 비용이 낮다. 이 기능은 스펙 §6에서 "Places API 호출이라 가장 적은 노력으로 화면이 채워진다"고 평가되어 있으므로 지도·리스트·배지·카드 모두 읽기 전용 조회 화면으로만 구현하고, 작성·예약·추천 로직은 만들지 않는다.

**Tech Stack:** Flutter 3.x / Riverpod / dio / `google_maps_flutter` / `geolocator` / `url_launcher`(전화 연결)

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §6-⑥, §7

## Global Constraints

- **Android 전용.** iOS 분기 코드를 추가하지 않는다.
- **화면은 `apiClientProvider`를 직접 재사용한다.** 개별 API 파일에서 새 `Dio` 인스턴스를 만들지 않는다 (Phase 0 Task 9, `app/lib/core/network/api_client.dart`).
- **패키지 루트**: `com.travelfootsteps`. Dart import 경로는 `app/lib/features/nearby/` 하위로 통일한다.
- **비밀정보를 커밋하지 않는다.** Maps API 키는 Phase 0 Task 2에서 이미 로컬에 발급되어 있다고 가정한다(`app/android/app/google-services.json`, `android/local.properties`의 `MAPS_API_KEY` 등). 새 키를 커밋하지 않는다.
- **브랜치 전략**: `feature/*`에서 시작해 `develop`으로 PR, 2인 승인, 매주 금요일 `develop` 머지.
- **제외 범위** (스펙 §6-⑥ 명시): 리뷰·평점 작성, 예약, 일정 자동 추천. 이 계획서의 어떤 태스크도 이 기능을 만들지 않는다.
- **여유가 없어질 때 가장 먼저 잘리는 기능이다** (스펙 §10 "자르는 순서" 1번). Task를 최대한 독립적으로 쪼개, 시간이 부족하면 Task 5(통합) 이전 단계까지만 완료해도 개별 데이터(Places 리스트, 경보 배지, 공관 카드)가 부분적으로 동작하도록 설계한다.

---

## 서버 계약 확정 (이 계획서 범위)

스펙 §7은 세 엔드포인트의 존재만 명시하고 파라미터·응답 스키마는 정의하지 않았다. Plan F는 앱 쪽에서 아래 계약을 전제로 구현한다. R1이 이 계약과 다르게 구현했다면 Task 2/4의 `fromJson`만 수정하면 된다 — 화면 로직에는 영향이 없다.

```
GET /api/places/nearby?lat={lat}&lng={lng}&radius={meters}&category={CATEGORY}
  CATEGORY ∈ TOURIST | RESTAURANT | PHARMACY | ATM
  200 → [{ "id": "...", "name": "...", "category": "RESTAURANT",
           "address": "...", "lat": 0.0, "lng": 0.0 }]

GET /api/countries/{iso2}/alerts
  200 → [{ "id": "...", "level": 1..4, "region": "...",
           "title": "...", "issuedAt": "2026-09-01T00:00:00Z" }]

GET /api/countries/{iso2}/embassies
  200 → [{ "id": "...", "type": "대사관|총영사관|분관", "name": "...",
           "lat": 0.0, "lng": 0.0, "phone": "...",
           "emergencyPhone": "...", "address": "..." }]
```

모두 `apiClientProvider`의 `AuthInterceptor`가 자동으로 `Authorization` 헤더를 붙이므로 개별 호출부에서 헤더를 신경 쓰지 않는다.

---

## File Structure (이 계획서가 만드는 부분만)

```
app/
├── lib/
│   ├── features/nearby/
│   │   ├── nearby_page.dart                 Modify — Phase 0 껍데기를 실제 화면으로 교체 (Task 5)
│   │   ├── models/
│   │   │   ├── place.dart                   Place 모델 + PlaceCategory enum (Task 2)
│   │   │   ├── travel_alert.dart            TravelAlert 모델 (Task 4)
│   │   │   └── embassy.dart                 Embassy 모델 (Task 4)
│   │   ├── api/
│   │   │   ├── places_api.dart              GET /api/places/nearby (Task 2)
│   │   │   ├── travel_alert_api.dart        GET /api/countries/{iso2}/alerts (Task 4)
│   │   │   └── embassy_api.dart             GET /api/countries/{iso2}/embassies (Task 4)
│   │   ├── location/
│   │   │   └── location_repository.dart     현재 위치 획득 추상화 (Task 1)
│   │   ├── providers/
│   │   │   └── nearby_selection_providers.dart  카테고리·국가 선택 상태 (Task 1)
│   │   └── widgets/
│   │       ├── category_filter_tabs.dart    관광지/음식점/약국/ATM 탭 (Task 2)
│   │       ├── place_list_tile.dart         리스트 항목 (Task 2)
│   │       ├── nearby_map_view.dart         지도 + 마커 (Task 3)
│   │       ├── alert_badge.dart             여행경보 1~4단계 배지 (Task 4)
│   │       └── embassy_card.dart            재외공관 카드 (Task 4)
│   └── pubspec.yaml                         Modify — geolocator, google_maps_flutter, url_launcher 확인/추가 (Task 1, 3, 4)
└── test/nearby/
    ├── location_repository_test.dart        (Task 1)
    ├── nearby_selection_providers_test.dart  (Task 1)
    ├── places_api_test.dart                  (Task 2)
    ├── alert_badge_test.dart                 (Task 4)
    ├── travel_alert_api_test.dart            (Task 4)
    ├── embassy_api_test.dart                 (Task 4)
    └── nearby_page_test.dart                 (Task 5, 통합)
```

**분리 원칙**: `location/`은 GPS 획득만 책임지고 화면을 모른다. `api/`의 세 파일은 서로 독립적이라 병렬로 만들 수 있고, 실패해도 나머지 둘에 영향을 주지 않는다 — 예산이 부족해 Task 4를 자르더라도 Task 2(Places)만으로 화면이 부분 동작한다.

---

### Task 1: 현재 위치 획득 + 카테고리/국가 선택 상태

**Files:**
- Create: `app/lib/features/nearby/location/location_repository.dart`
- Create: `app/lib/features/nearby/providers/nearby_selection_providers.dart`
- Modify: `app/pubspec.yaml` (geolocator 확인)
- Modify: `app/android/app/src/main/AndroidManifest.xml` (위치 권한 확인)
- Test: `app/test/nearby/location_repository_test.dart`
- Test: `app/test/nearby/nearby_selection_providers_test.dart`

**Interfaces:**
- Consumes: Phase 0 Task 9의 `countryListProvider` (`app/lib/core/network/country_api.dart`, `FutureProvider<List<Country>>`, `Country.isoAlpha2`)
- Produces:
  - `abstract class LocationRepository { Future<Position> getCurrentPosition(); }` — geolocator를 직접 다루지 않도록 화면과 분리 (테스트에서 GPS 없이 대체 가능)
  - `class LocationPermissionDeniedException implements Exception`
  - `locationRepositoryProvider` (`Provider<LocationRepository>`)
  - `currentPositionProvider` (`FutureProvider<Position>`)
  - `nearbyCategoryProvider` (`StateProvider<PlaceCategory>`, 초기값 `PlaceCategory.tourist`) — Task 2가 사용
  - `selectedCountryProvider` (`StateProvider<String?>`, 초기값 `null`) — Task 4, 5가 사용
  - Task 2의 `PlaceCategory` enum을 import해서 쓴다 (Task 2에서 먼저 정의되지 않았다면 이 태스크에서 `models/place.dart`에 enum만 먼저 만들어도 된다 — 아래 Step 3에서 처리)

- [ ] **Step 1: `PlaceCategory` enum 선(先)정의**

Task 2가 `Place` 모델과 함께 이 enum을 완성하지만, Task 1의 provider가 먼저 필요로 하므로 여기서 enum만 만든다. `app/lib/features/nearby/models/place.dart`:

```dart
enum PlaceCategory {
  tourist('TOURIST', '관광지'),
  restaurant('RESTAURANT', '음식점'),
  pharmacy('PHARMACY', '약국'),
  atm('ATM', 'ATM');

  const PlaceCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;
}
```

- [ ] **Step 2: 실패하는 위치 저장소 테스트 작성**

`app/test/nearby/location_repository_test.dart`:

```dart
import 'package:app/features/nearby/location/location_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingLocationRepository implements LocationRepository {
  @override
  Future<Position> getCurrentPosition() {
    throw const LocationPermissionDeniedException();
  }
}

void main() {
  test('권한이 거부되면 LocationPermissionDeniedException을 던진다', () {
    final repository = _ThrowingLocationRepository();
    expect(
      () => repository.getCurrentPosition(),
      throwsA(isA<LocationPermissionDeniedException>()),
    );
  });
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/location_repository_test.dart
```

기대: 컴파일 실패 — `location_repository.dart`, `Position` 타입(geolocator 패키지)을 찾을 수 없음.

- [ ] **Step 4: geolocator 의존성 확인/추가**

`app/pubspec.yaml`의 `dependencies:` 아래에 이미 `geolocator:`가 있는지 확인한다(Plan C가 먼저 완료되었으므로 이미 있을 가능성이 높다). 없으면 추가:

```yaml
  geolocator: ^13.0.1
```

```bash
cd app && flutter pub get
```

- [ ] **Step 5: `LocationRepository` 구현**

`app/lib/features/nearby/location/location_repository.dart`:

```dart
import 'package:geolocator/geolocator.dart';

class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException();
}

class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();
}

abstract class LocationRepository {
  Future<Position> getCurrentPosition();
}

class GeolocatorLocationRepository implements LocationRepository {
  @override
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationPermissionDeniedException();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException();
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
  }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/location_repository_test.dart
```

기대: PASS.

- [ ] **Step 7: AndroidManifest 위치 권한 확인**

`app/android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 바로 아래에 다음 두 줄이 이미 있는지 확인한다(Plan C가 발걸음 기록을 위해 추가했을 가능성이 높다). 없으면 추가:

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

- [ ] **Step 8: 실패하는 선택 상태 테스트 작성**

`app/test/nearby/nearby_selection_providers_test.dart`:

```dart
import 'package:app/features/nearby/models/place.dart';
import 'package:app/features/nearby/providers/nearby_selection_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('카테고리 기본값은 관광지다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(nearbyCategoryProvider), PlaceCategory.tourist);
  });

  test('카테고리를 바꾸면 provider 값이 갱신된다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(nearbyCategoryProvider.notifier).state = PlaceCategory.atm;

    expect(container.read(nearbyCategoryProvider), PlaceCategory.atm);
  });

  test('국가 선택 기본값은 null이다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(selectedCountryProvider), isNull);
  });
}
```

- [ ] **Step 9: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/nearby_selection_providers_test.dart
```

기대: 컴파일 실패 — `nearby_selection_providers.dart`를 찾을 수 없음.

- [ ] **Step 10: provider 구현**

`app/lib/features/nearby/providers/nearby_selection_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../location/location_repository.dart';
import '../models/place.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return GeolocatorLocationRepository();
});

final currentPositionProvider = FutureProvider((ref) {
  return ref.watch(locationRepositoryProvider).getCurrentPosition();
});

/// 현재 선택된 Places 필터 카테고리. 기본값은 관광지.
final nearbyCategoryProvider =
    StateProvider<PlaceCategory>((ref) => PlaceCategory.tourist);

/// 여행경보·재외공관 조회 대상 국가(ISO2). 사용자가 직접 고르기 전에는 null이며,
/// 화면에서는 null일 때 국가 목록의 첫 항목을 기본값으로 표시한다 (Task 5).
final selectedCountryProvider = StateProvider<String?>((ref) => null);
```

- [ ] **Step 11: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/nearby_selection_providers_test.dart
```

기대: PASS.

- [ ] **Step 12: 전체 검사 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/nearby/location app/lib/features/nearby/providers \
        app/lib/features/nearby/models/place.dart app/pubspec.yaml \
        app/android/app/src/main/AndroidManifest.xml app/test/nearby
git commit -m "feat(nearby): 위치 획득과 카테고리/국가 선택 상태 추가"
```

---

### Task 2: Places API 연동 + 필터 탭 + 리스트

**Files:**
- Modify: `app/lib/features/nearby/models/place.dart` (Task 1에서 만든 enum에 `Place` 모델 추가)
- Create: `app/lib/features/nearby/api/places_api.dart`
- Create: `app/lib/features/nearby/widgets/category_filter_tabs.dart`
- Create: `app/lib/features/nearby/widgets/place_list_tile.dart`
- Test: `app/test/nearby/places_api_test.dart`

**Interfaces:**
- Consumes: Task 1의 `nearbyCategoryProvider`, `currentPositionProvider`; Phase 0 Task 9의 `apiClientProvider`
- Produces:
  - `class Place { id, name, category(PlaceCategory), address, lat, lng }` + `Place.fromJson`
  - `nearbyPlacesProvider` (`FutureProvider<List<Place>>`) — `currentPositionProvider`와 `nearbyCategoryProvider`를 함께 watch해서 위치나 카테고리가 바뀌면 자동 재조회
  - `CategoryFilterTabs` 위젯 — Task 5가 `NearbyPage` 상단에 배치
  - `PlaceListTile` 위젯 — Task 5가 하단 리스트에서 사용

- [ ] **Step 1: `Place` 모델의 실패하는 테스트 작성**

`app/test/nearby/places_api_test.dart`:

```dart
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
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/places_api_test.dart
```

기대: 컴파일 실패 — `places_api.dart`, `Place.fromJson`, `fetchNearbyPlaces`를 찾을 수 없음.

- [ ] **Step 3: `Place` 모델 추가**

`app/lib/features/nearby/models/place.dart`에 Step 1(Task 1)의 enum 뒤에 이어서 추가:

```dart
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final String address;
  final double lat;
  final double lng;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: json['id'] as String,
        name: json['name'] as String,
        category: PlaceCategory.values.firstWhere(
          (c) => c.apiValue == json['category'],
          orElse: () => PlaceCategory.tourist,
        ),
        address: json['address'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );
}
```

- [ ] **Step 4: `places_api.dart` 구현**

`app/lib/features/nearby/api/places_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/place.dart';
import '../providers/nearby_selection_providers.dart';

/// 반경(m). 도보 이동권을 벗어나지 않는 범위로 고정한다.
const nearbySearchRadiusMeters = 1500;

Future<List<Place>> fetchNearbyPlaces(
  Dio dio, {
  required double lat,
  required double lng,
  required PlaceCategory category,
  int radius = nearbySearchRadiusMeters,
}) async {
  final response = await dio.get<List<dynamic>>(
    '/api/places/nearby',
    queryParameters: {
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'category': category.apiValue,
    },
  );
  return response.data!
      .map((e) => Place.fromJson(e as Map<String, dynamic>))
      .toList();
}

final nearbyPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  final category = ref.watch(nearbyCategoryProvider);
  final dio = ref.watch(apiClientProvider);

  return fetchNearbyPlaces(
    dio,
    lat: position.latitude,
    lng: position.longitude,
    category: category,
  );
});
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/places_api_test.dart
```

기대: PASS.

- [ ] **Step 6: 필터 탭 위젯**

`app/lib/features/nearby/widgets/category_filter_tabs.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place.dart';
import '../providers/nearby_selection_providers.dart';

class CategoryFilterTabs extends ConsumerWidget {
  const CategoryFilterTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(nearbyCategoryProvider);

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: PlaceCategory.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = PlaceCategory.values[i];
          return ChoiceChip(
            label: Text(category.label),
            selected: category == selected,
            onSelected: (_) =>
                ref.read(nearbyCategoryProvider.notifier).state = category,
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 7: 리스트 항목 위젯**

`app/lib/features/nearby/widgets/place_list_tile.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/place.dart';

class PlaceListTile extends StatelessWidget {
  const PlaceListTile({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(place.name),
      subtitle: Text(place.address),
      trailing: Text(place.category.label),
    );
  }
}
```

- [ ] **Step 8: 전체 검사 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/nearby/models/place.dart app/lib/features/nearby/api/places_api.dart \
        app/lib/features/nearby/widgets/category_filter_tabs.dart \
        app/lib/features/nearby/widgets/place_list_tile.dart app/test/nearby/places_api_test.dart
git commit -m "feat(nearby): Places 조회와 카테고리 필터 리스트 추가"
```

---

### Task 3: 지도 마커 표시

**Files:**
- Create: `app/lib/features/nearby/widgets/nearby_map_view.dart`
- Modify: `app/pubspec.yaml` (`google_maps_flutter` 확인)

**Interfaces:**
- Consumes: Task 2의 `Place` 모델, Task 4의 `Embassy` 모델(아래에서 먼저 시그니처만 정의하고 Task 4가 실체를 만든다)
- Produces: `NearbyMapView` 위젯 — `Position center`, `List<Place> places`, `List<Embassy> embassies`를 받아 지도를 그린다. Task 5가 `NearbyPage` 상단 절반에 배치.

> **Plan C 재사용 메모**: Plan C가 발걸음 지도를 위해 카메라 이동·마커 클러스터링을 포함한 공용 지도 컴포넌트를 이미 뽑아 두었다면(`app/lib/features/footsteps/widgets/` 하위 등), 이 태스크를 건너뛰고 그 컴포넌트에 마커 리스트를 주입하는 방식으로 대체한다. 그런 컴포넌트가 없다면 아래처럼 이 화면 전용으로 최소 구현한다 — `GoogleMap`을 직접 감싸는 20여 줄짜리 위젯이라 나중에 공용화해도 교체 비용이 낮다.

- [ ] **Step 1: `google_maps_flutter` 의존성 확인**

`app/pubspec.yaml`에 이미 있는지 확인한다(Plan C가 추가했을 가능성이 높다). 없으면 추가:

```yaml
  google_maps_flutter: ^2.9.0
```

```bash
cd app && flutter pub get
```

- [ ] **Step 2: `NearbyMapView` 구현**

이 위젯은 순수 조립 로직이라 자동화 테스트보다 수동 확인이 비용 대비 효율적이다(`GoogleMap`은 플랫폼 뷰라 위젯 테스트로 렌더링을 검증할 수 없다) — Task 5의 통합 단계에서 실기기/에뮬레이터로 확인한다.

`app/lib/features/nearby/widgets/nearby_map_view.dart`:

```dart
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

import '../models/embassy.dart';
import '../models/place.dart';

class NearbyMapView extends StatelessWidget {
  const NearbyMapView({
    super.key,
    required this.center,
    required this.places,
    required this.embassies,
  });

  final Position center;
  final List<Place> places;
  final List<Embassy> embassies;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      for (final place in places)
        Marker(
          markerId: MarkerId('place-${place.id}'),
          position: LatLng(place.lat, place.lng),
          infoWindow: InfoWindow(title: place.name, snippet: place.address),
        ),
      for (final embassy in embassies)
        Marker(
          markerId: MarkerId('embassy-${embassy.id}'),
          position: LatLng(embassy.lat, embassy.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(title: embassy.name, snippet: embassy.address),
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(center.latitude, center.longitude),
        zoom: 15,
      ),
      markers: markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
    );
  }
}
```

- [ ] **Step 3: 정적 분석 확인 (컴파일만 확인, `Embassy`는 Task 4에서 완성됨)**

Task 4를 먼저 병행하지 않는 한 `flutter analyze`가 `embassy.dart` 미존재로 실패하는 것이 정상이다. Task 4 완료 후 다시 확인한다.

- [ ] **Step 4: 커밋**

```bash
git add app/lib/features/nearby/widgets/nearby_map_view.dart app/pubspec.yaml
git commit -m "feat(nearby): Places/재외공관 마커를 표시하는 지도 위젯 추가"
```

---

### Task 4: 여행경보 + 재외공관 API 연동

**Files:**
- Create: `app/lib/features/nearby/models/travel_alert.dart`
- Create: `app/lib/features/nearby/models/embassy.dart`
- Create: `app/lib/features/nearby/api/travel_alert_api.dart`
- Create: `app/lib/features/nearby/api/embassy_api.dart`
- Create: `app/lib/features/nearby/widgets/alert_badge.dart`
- Create: `app/lib/features/nearby/widgets/embassy_card.dart`
- Modify: `app/pubspec.yaml` (`url_launcher` 추가)
- Test: `app/test/nearby/alert_badge_test.dart`
- Test: `app/test/nearby/travel_alert_api_test.dart`
- Test: `app/test/nearby/embassy_api_test.dart`

**Interfaces:**
- Consumes: Task 1의 `selectedCountryProvider`; Phase 0 Task 9의 `apiClientProvider`
- Produces:
  - `class TravelAlert { id, level(int), region, title, issuedAt(DateTime) }` + `fromJson`
  - `class Embassy { id, type, name, lat, lng, phone, emergencyPhone, address }` + `fromJson`
  - `travelAlertsProvider` (`FutureProvider.family<List<TravelAlert>, String>`, 인자는 iso2)
  - `embassiesProvider` (`FutureProvider.family<List<Embassy>, String>`, 인자는 iso2)
  - `AlertBadge` 위젯 — `level`(1~4)을 받아 색상 배지 렌더링
  - `EmbassyCard` 위젯 — 전화 걸기 버튼 포함

- [ ] **Step 1: 배지 색상 규칙의 실패하는 테스트 작성**

`app/test/nearby/alert_badge_test.dart`:

```dart
import 'package:app/features/nearby/widgets/alert_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('1~4단계가 각각 다른 색과 라벨을 가진다', () {
    expect(alertColorForLevel(1), Colors.blue);
    expect(alertColorForLevel(2), Colors.yellow.shade800);
    expect(alertColorForLevel(3), Colors.orange);
    expect(alertColorForLevel(4), Colors.red);
    expect(alertLabelForLevel(1), '남색경보 (여행유의)');
    expect(alertLabelForLevel(4), '흑색경보 (여행금지)');
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/alert_badge_test.dart
```

기대: 컴파일 실패 — `alert_badge.dart`를 찾을 수 없음.

- [ ] **Step 3: `TravelAlert`, `Embassy` 모델 작성**

`app/lib/features/nearby/models/travel_alert.dart`:

```dart
class TravelAlert {
  const TravelAlert({
    required this.id,
    required this.level,
    required this.region,
    required this.title,
    required this.issuedAt,
  });

  final String id;
  final int level;
  final String region;
  final String title;
  final DateTime issuedAt;

  factory TravelAlert.fromJson(Map<String, dynamic> json) => TravelAlert(
        id: json['id'] as String,
        level: json['level'] as int,
        region: json['region'] as String,
        title: json['title'] as String,
        issuedAt: DateTime.parse(json['issuedAt'] as String),
      );
}
```

`app/lib/features/nearby/models/embassy.dart`:

```dart
class Embassy {
  const Embassy({
    required this.id,
    required this.type,
    required this.name,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.emergencyPhone,
    required this.address,
  });

  final String id;
  final String type;
  final String name;
  final double lat;
  final double lng;
  final String phone;
  final String emergencyPhone;
  final String address;

  factory Embassy.fromJson(Map<String, dynamic> json) => Embassy(
        id: json['id'] as String,
        type: json['type'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        phone: json['phone'] as String,
        emergencyPhone: json['emergencyPhone'] as String,
        address: json['address'] as String,
      );
}
```

- [ ] **Step 4: `AlertBadge` 위젯 구현**

`app/lib/features/nearby/widgets/alert_badge.dart`:

```dart
import 'package:flutter/material.dart';

Color alertColorForLevel(int level) {
  switch (level) {
    case 1:
      return Colors.blue;
    case 2:
      return Colors.yellow.shade800;
    case 3:
      return Colors.orange;
    case 4:
    default:
      return Colors.red;
  }
}

String alertLabelForLevel(int level) {
  switch (level) {
    case 1:
      return '남색경보 (여행유의)';
    case 2:
      return '황색경보 (여행자제)';
    case 3:
      return '적색경보 (철수권고)';
    case 4:
    default:
      return '흑색경보 (여행금지)';
  }
}

class AlertBadge extends StatelessWidget {
  const AlertBadge({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final color = alertColorForLevel(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        alertLabelForLevel(level),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/alert_badge_test.dart
```

기대: PASS.

- [ ] **Step 6: 여행경보 API의 실패하는 테스트 작성**

`app/test/nearby/travel_alert_api_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/nearby/api/travel_alert_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GET /api/countries/{iso2}/alerts 를 호출해 파싱한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _FakeAlertsAdapter();

    final alerts = await fetchTravelAlerts(dio, iso2: 'VN');

    expect(alerts, hasLength(1));
    expect(alerts.first.level, 2);
    expect(alerts.first.region, '전역');
  });
}

class _FakeAlertsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.path, '/api/countries/VN/alerts');
    final json = jsonEncode([
      {
        'id': 'a1',
        'level': 2,
        'region': '전역',
        'title': '황색경보 발령',
        'issuedAt': '2026-08-01T00:00:00Z',
      },
    ]);
    return ResponseBody.fromString(json, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 7: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/travel_alert_api_test.dart
```

기대: 컴파일 실패 — `travel_alert_api.dart`를 찾을 수 없음.

- [ ] **Step 8: `travel_alert_api.dart` 구현**

`app/lib/features/nearby/api/travel_alert_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/travel_alert.dart';

Future<List<TravelAlert>> fetchTravelAlerts(
  Dio dio, {
  required String iso2,
}) async {
  final response =
      await dio.get<List<dynamic>>('/api/countries/$iso2/alerts');
  return response.data!
      .map((e) => TravelAlert.fromJson(e as Map<String, dynamic>))
      .toList();
}

final travelAlertsProvider =
    FutureProvider.family<List<TravelAlert>, String>((ref, iso2) async {
  final dio = ref.watch(apiClientProvider);
  return fetchTravelAlerts(dio, iso2: iso2);
});
```

- [ ] **Step 9: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/travel_alert_api_test.dart
```

기대: PASS.

- [ ] **Step 10: 재외공관 API의 실패하는 테스트 작성**

`app/test/nearby/embassy_api_test.dart`:

```dart
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
        'id': 'e1',
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
```

- [ ] **Step 11: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/embassy_api_test.dart
```

기대: 컴파일 실패 — `embassy_api.dart`를 찾을 수 없음.

- [ ] **Step 12: `embassy_api.dart` 구현**

`app/lib/features/nearby/api/embassy_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/embassy.dart';

Future<List<Embassy>> fetchEmbassies(
  Dio dio, {
  required String iso2,
}) async {
  final response =
      await dio.get<List<dynamic>>('/api/countries/$iso2/embassies');
  return response.data!
      .map((e) => Embassy.fromJson(e as Map<String, dynamic>))
      .toList();
}

final embassiesProvider =
    FutureProvider.family<List<Embassy>, String>((ref, iso2) async {
  final dio = ref.watch(apiClientProvider);
  return fetchEmbassies(dio, iso2: iso2);
});
```

- [ ] **Step 13: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/embassy_api_test.dart
```

기대: PASS.

- [ ] **Step 14: `url_launcher` 의존성 추가**

`app/pubspec.yaml`의 `dependencies:` 아래:

```yaml
  url_launcher: ^6.3.1
```

```bash
cd app && flutter pub get
```

- [ ] **Step 15: `EmbassyCard` 위젯 구현**

`app/lib/features/nearby/widgets/embassy_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/embassy.dart';

class EmbassyCard extends StatelessWidget {
  const EmbassyCard({super.key, required this.embassy});

  final Embassy embassy;

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${embassy.type} · ${embassy.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(embassy.address),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _call(embassy.phone),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('대표전화'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _call(embassy.emergencyPhone),
                  icon: const Icon(Icons.emergency_outlined, size: 18),
                  label: const Text('긴급연락'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 16: 전체 검사 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/nearby/models/travel_alert.dart app/lib/features/nearby/models/embassy.dart \
        app/lib/features/nearby/api/travel_alert_api.dart app/lib/features/nearby/api/embassy_api.dart \
        app/lib/features/nearby/widgets/alert_badge.dart app/lib/features/nearby/widgets/embassy_card.dart \
        app/pubspec.yaml app/test/nearby/alert_badge_test.dart app/test/nearby/travel_alert_api_test.dart \
        app/test/nearby/embassy_api_test.dart
git commit -m "feat(nearby): 여행경보·재외공관 조회와 배지/카드 위젯 추가"
```

---

### Task 5: `NearbyPage` 통합

**Files:**
- Modify: `app/lib/features/nearby/nearby_page.dart`
- Test: `app/test/nearby/nearby_page_test.dart`

**Interfaces:**
- Consumes: Task 1의 `selectedCountryProvider`, `currentPositionProvider`; Task 2의 `nearbyPlacesProvider`, `CategoryFilterTabs`, `PlaceListTile`; Task 3의 `NearbyMapView`; Task 4의 `travelAlertsProvider`, `embassiesProvider`, `AlertBadge`, `EmbassyCard`; Phase 0 Task 9의 `countryListProvider`
- Produces: 완성된 `NearbyPage` — Plan F의 최종 산출물. 이후 계획서는 이 화면을 수정하지 않는다.

- [ ] **Step 1: 실패하는 통합 위젯 테스트 작성**

실제 GPS·지도·네트워크 없이 조립 로직만 검증한다. `GoogleMap`은 플랫폼 뷰라 위젯 테스트에서 렌더링되지 않으므로, 지도를 감싸는 영역이 존재하는지까지만 확인하고 나머지(필터 탭, 배지, 공관 카드)는 실제 데이터로 검증한다.

`app/test/nearby/nearby_page_test.dart`:

```dart
import 'package:app/core/network/country_api.dart';
import 'package:app/features/nearby/api/embassy_api.dart';
import 'package:app/features/nearby/api/places_api.dart';
import 'package:app/features/nearby/api/travel_alert_api.dart';
import 'package:app/features/nearby/models/embassy.dart';
import 'package:app/features/nearby/models/place.dart';
import 'package:app/features/nearby/models/travel_alert.dart';
import 'package:app/features/nearby/nearby_page.dart';
import 'package:app/features/nearby/providers/nearby_selection_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  final fakePosition = Position(
    latitude: 21.02,
    longitude: 105.83,
    timestamp: DateTime(2026, 9, 7),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  const country =
      Country(isoAlpha2: 'VN', nameKo: '베트남', nameEn: 'Vietnam', continent: '아시아', tier: 'A');

  testWidgets('경보 배지와 공관 카드, 필터 탭이 함께 보인다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentPositionProvider.overrideWith((ref) async => fakePosition),
          countryListProvider.overrideWith((ref) async => [country]),
          nearbyPlacesProvider.overrideWith((ref) async => const [
                Place(
                  id: 'p1',
                  name: '호안끼엠 호수',
                  category: PlaceCategory.tourist,
                  address: '하노이',
                  lat: 21.03,
                  lng: 105.85,
                ),
              ]),
          travelAlertsProvider.overrideWith((ref, iso2) async => [
                TravelAlert(
                  id: 'a1',
                  level: 2,
                  region: '전역',
                  title: '황색경보',
                  issuedAt: DateTime(2026, 8, 1),
                ),
              ]),
          embassiesProvider.overrideWith((ref, iso2) async => const [
                Embassy(
                  id: 'e1',
                  type: '대사관',
                  name: '주베트남대한민국대사관',
                  lat: 21.02,
                  lng: 105.83,
                  phone: '+84-24-xxx-xxxx',
                  emergencyPhone: '+84-90-xxx-xxxx',
                  address: '하노이',
                ),
              ]),
        ],
        child: const MaterialApp(home: NearbyPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('관광지'), findsOneWidget);
    expect(find.text('호안끼엠 호수'), findsOneWidget);
    expect(find.text('황색경보 (여행자제)'), findsOneWidget);
    expect(find.textContaining('주베트남대한민국대사관'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/nearby/nearby_page_test.dart
```

기대: 컴파일 실패 또는 실패 — `NearbyPage`가 아직 `'주변'` 텍스트만 표시하는 Phase 0 껍데기이므로 위 `expect`들이 매치되지 않는다.

- [ ] **Step 3: `NearbyPage` 구현**

`app/lib/features/nearby/nearby_page.dart` 전체를 아래로 교체한다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_api.dart';
import 'api/embassy_api.dart';
import 'api/places_api.dart';
import 'api/travel_alert_api.dart';
import 'models/embassy.dart';
import 'models/travel_alert.dart';
import 'providers/nearby_selection_providers.dart';
import 'widgets/alert_badge.dart';
import 'widgets/category_filter_tabs.dart';
import 'widgets/embassy_card.dart';
import 'widgets/nearby_map_view.dart';
import 'widgets/place_list_tile.dart';

class NearbyPage extends ConsumerWidget {
  const NearbyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(currentPositionProvider);
    final countries = ref.watch(countryListProvider);
    final selectedIso2 = ref.watch(selectedCountryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('주변'),
        actions: [
          countries.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final effective = selectedIso2 ?? list.first.isoAlpha2;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButton<String>(
                  value: effective,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in list)
                      DropdownMenuItem(value: c.isoAlpha2, child: Text(c.nameKo)),
                  ],
                  onChanged: (value) =>
                      ref.read(selectedCountryProvider.notifier).state = value,
                ),
              );
            },
          ),
        ],
      ),
      body: position.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '현재 위치를 가져오지 못했습니다\n위치 권한을 확인해 주세요',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (pos) {
          // 국가 목록이 아직 없으면(로딩·에러 중) iso2 관련 조회는 전부 건너뛴다.
          final iso2 = countries.asData?.value.isEmpty ?? true
              ? null
              : (selectedIso2 ?? countries.asData!.value.first.isoAlpha2);

          final places = ref.watch(nearbyPlacesProvider);
          final AsyncValue<List<TravelAlert>> alerts = iso2 == null
              ? const AsyncValue.data([])
              : ref.watch(travelAlertsProvider(iso2));
          final AsyncValue<List<Embassy>> embassies = iso2 == null
              ? const AsyncValue.data([])
              : ref.watch(embassiesProvider(iso2));

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 240,
                  child: NearbyMapView(
                    center: pos,
                    places: places.asData?.value ?? const [],
                    embassies: embassies.asData?.value ?? const [],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CategoryFilterTabs(),
                ),
              ),
              if ((alerts.asData?.value ?? const []).isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final a in alerts.asData!.value) AlertBadge(level: a.level),
                      ],
                    ),
                  ),
                ),
              places.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('주변 정보를 불러오지 못했습니다\n$e'),
                  ),
                ),
                data: (list) => SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => PlaceListTile(place: list[i]),
                ),
              ),
              if ((embassies.asData?.value ?? const []).isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      '재외공관',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: embassies.asData!.value.length,
                  itemBuilder: (context, i) =>
                      EmbassyCard(embassy: embassies.asData!.value[i]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/nearby/nearby_page_test.dart
```

기대: PASS.

- [ ] **Step 5: 실기기/에뮬레이터 수동 확인**

```bash
cd server && ./gradlew bootRun
```

```bash
cd app && flutter run
```

확인 항목:
1. '주변' 탭 진입 시 위치 권한 요청 다이얼로그가 뜨고, 허용하면 지도가 현재 위치를 중심으로 표시된다
2. 필터 탭(관광지/음식점/약국/ATM)을 바꾸면 지도 마커와 하단 리스트가 함께 갱신된다
3. 상단 드롭다운으로 국가를 바꾸면 여행경보 배지 색상·문구와 재외공관 카드가 갱신된다
4. 공관 카드의 "긴급연락" 버튼을 누르면 전화 앱이 열린다(에뮬레이터에서는 다이얼러 화면 전환까지 확인)
5. 위치 권한을 거부하면 에러 메시지가 표시되고 앱이 크래시하지 않는다

- [ ] **Step 6: 전체 검사**

```bash
cd app && flutter analyze && flutter test
```

기대: 전체 PASS. `flutter analyze`가 Task 3에서 남긴 `Embassy` 미해결 경고까지 이 시점에는 모두 해소되어 있어야 한다.

- [ ] **Step 7: 커밋과 PR**

```bash
git add app/lib/features/nearby/nearby_page.dart app/test/nearby/nearby_page_test.dart
git commit -m "feat(nearby): 지도+리스트+여행경보+재외공관 통합 화면 완성 (Plan F 완료)"
git push origin HEAD
```

`develop`으로 PR을 올리고 2인 승인을 받는다. CI의 `Flutter` job이 초록인지 확인한다.

---

## Plan F 완료 체크리스트

- [ ] '주변' 탭에서 현재 위치 기준 관광지/음식점/약국/ATM 필터가 동작한다
- [ ] 지도 마커와 하단 리스트가 같은 데이터로 동기화되어 있다
- [ ] 선택한 국가의 여행경보 1~4단계가 배지로 표시된다
- [ ] 선택한 국가의 재외공관 연락처·위치가 카드로 표시되고 전화 연결이 동작한다
- [ ] 리뷰·평점 작성, 예약, 일정 자동 추천 기능이 존재하지 않는다 (스펙 §6-⑥ 제외 범위 확인)
- [ ] `flutter analyze`, `flutter test` 모두 PASS
