# 여행계획 중심 재구성 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 여행 한 건을 앱의 중심 단위로 만든다 — 여행 탭은 내 여행 목록, 준비물 탭은 선택된 여행의 서버 체크리스트, 지갑은 여행별 가계부.

**Architecture:** 서버는 `GET /api/trips`(요약 목록)와 `DELETE /api/trips/{id}`만 추가한다(스키마 변경 없음). 앱은 목록을 SharedPreferences에 캐시하는 `tripListProvider`, 선택된 여행 id(`selectedTripIdProvider`), 기본 여행을 고르는 순수 함수 `resolveSelectedTrip`을 중심으로 여행 탭·준비물 탭·지갑을 다시 잇는다. 지갑 drift DB는 `isoAlpha2` 대신 `tripId`로 기록을 묶고, 기존 데이터는 버린다.

**Tech Stack:** Spring Boot 3 / Java 21 / JPA / Testcontainers(CI), Flutter / Riverpod 3 / go_router / dio / drift / shared_preferences

**Spec:** `docs/superpowers/specs/2026-10-11-trip-centric-design.md`

## Global Constraints

- 브랜치 `trip-list`. 커밋에 `Co-Authored-By`·Claude·AI 트레일러를 넣지 않는다.
- 서버 프로덕션 코드(`server/src/main/**`)에는 Spring 개념 학습 주석을 단다. 테스트·Dart 코드에는 적용하지 않는다.
- 서버 테스트는 Testcontainers라 로컬(Docker 꺼짐)에서는 `./gradlew compileTestJava`로 컴파일만 확인하고, 실행은 CI가 한다.
- 앱 정적 분석은 `flutter analyze` 대신 `dart analyze`(이 PC에서 flutter analyze가 죽는다). 모든 명령은 `app/`에서 실행.
- drift 코드 생성: `dart run build_runner build --force-jit --delete-conflicting-outputs` 후 반드시 `git checkout -- lib/core/db/app_database.g.dart`(관계없는 파일이 같이 바뀐다).
- 탭 라벨은 `'여행'`. 날짜 범위 표기는 `M/d~M/d`.
- SharedPreferences 키: 목록 캐시 `trips.cache.v1`, 선택된 여행 `selected_trip_id`, 보조배터리 체크 `checklist_powerbank_<tripId>`.
- 판정 배지 짧은 라벨: `VISA_FREE_OK`→`무비자`, `VISA_FREE_EXCEEDED`→`무비자 초과`, `VISA_REQUIRED`→`비자 필요`, `UNVERIFIED`→`확인 필요`.

---

## File Structure

**Server (`server/src/main/java/com/travelfootsteps/trip/`)**
- Create `TripSummaryResponse.java` — 목록 한 줄 DTO
- Modify `TripRepository.java` — uid별 목록 쿼리
- Modify `TripController.java` — `list()`, `delete()`
- Modify test `server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java`

**App**
- Create `lib/features/visa/models/trip_summary.dart` — `TripSummary` + 날짜 범위 라벨
- Create `lib/features/visa/models/trip_checklist_item.dart` — `TripChecklistItem extends ChecklistItem`
- Modify `lib/features/visa/data/trip_api.dart` — 목록/삭제/체크리스트/체크
- Create `lib/features/visa/data/trip_list_providers.dart` — 캐시, 목록, 선택 여행, 분류·선택 규칙, 상세 family
- Create `lib/features/visa/data/trip_deletion.dart` — `TripDeleter`
- Delete `lib/features/visa/data/trip_providers.dart` (Task 6)
- Modify `lib/features/visa/visa_result_display.dart` — `verdictChipOf`
- Create `lib/features/visa/trip_list_page.dart` — 여행 탭 첫 화면
- Modify `lib/features/visa/visa_page.dart` — 새 여행 폼(`/visa/new`)
- Modify `lib/features/visa/visa_result_page.dart` — 여행 상세(`/visa/trip/:id`)
- Create `lib/features/checklist/data/power_bank_check_store.dart`
- Modify `lib/features/checklist/data/checklist_providers.dart`
- Delete `lib/features/checklist/data/checklist_checked_store.dart`
- Modify `lib/features/checklist/data/power_bank_item.dart` (주석만)
- Modify `lib/features/checklist/checklist_page.dart`
- Modify `lib/features/wallet/data/wallet_database.dart` (+ `.g.dart` 재생성), `lib/features/wallet/wallet_page.dart`
- Modify `lib/router.dart`

---

### Task 1: 서버 — 여행 목록·삭제 API

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/trip/TripSummaryResponse.java`
- Modify: `server/src/main/java/com/travelfootsteps/trip/TripRepository.java`
- Modify: `server/src/main/java/com/travelfootsteps/trip/TripController.java`
- Test: `server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java`

**Interfaces:**
- Produces: `GET /api/trips` → `[{id, countryIso2, countryNameKo, departDate:"yyyy-MM-dd", returnDate, verdict}]` 출발일 내림차순, 내 여행만. `DELETE /api/trips/{id}` → 204, 남의 여행/없음 → 404.

- [ ] **Step 1: 실패하는 테스트 작성**

`TripControllerTest.java`:

1. import 추가(기존 static import 옆):
```java
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
```
2. `TestBeans.tokenVerifier()`에 세 번째 사용자를 등록한다(목록 테스트가 다른 테스트의 여행과 섞이지 않게 전용 uid를 쓴다 — 이 클래스는 테스트 간 DB를 롤백하지 않는다):
```java
            stub.register("token-c", "uid-c");
```
3. 클래스 끝(마지막 `}` 앞)에 테스트 두 개 추가:
```java
    @Test
    void 여행_목록은_내_여행만_출발일_최신순으로_돌려준다() throws Exception {
        givenVietnamVisaFree45Days();
        Long older = createTrip("token-c", "VN",
                LocalDate.of(2026, 12, 1), LocalDate.of(2026, 12, 5), LocalDate.of(2030, 1, 1));
        Long newer = createTrip("token-c", "VN",
                LocalDate.of(2027, 2, 1), LocalDate.of(2027, 2, 5), LocalDate.of(2030, 1, 1));
        createTrip("token-a", "VN",
                LocalDate.of(2027, 3, 1), LocalDate.of(2027, 3, 5), LocalDate.of(2030, 1, 1));

        mockMvc.perform(get("/api/trips").header("Authorization", "Bearer token-c"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].id").value(newer.intValue()))
                .andExpect(jsonPath("$[0].countryIso2").value("VN"))
                .andExpect(jsonPath("$[0].countryNameKo").value("베트남"))
                .andExpect(jsonPath("$[0].departDate").value("2027-02-01"))
                .andExpect(jsonPath("$[0].returnDate").value("2027-02-05"))
                .andExpect(jsonPath("$[0].verdict").value("VISA_FREE_OK"))
                .andExpect(jsonPath("$[1].id").value(older.intValue()));
    }

    @Test
    void 여행_삭제는_소유자만_할_수_있고_일정과_체크리스트도_함께_지운다() throws Exception {
        givenVietnamVisaFree45Days();
        Long tripId = createTrip("token-a", "VN",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2027, 3, 15));

        mockMvc.perform(delete("/api/trips/" + tripId).header("Authorization", "Bearer token-b"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/trips/" + tripId).header("Authorization", "Bearer token-a"))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-a"))
                .andExpect(status().isNotFound());
        Integer tasks = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM trip_task WHERE trip_id = ?", Integer.class, tripId);
        Integer items = jdbcTemplate.queryForObject(
                "SELECT count(*) FROM trip_checklist WHERE trip_id = ?", Integer.class, tripId);
        assertThat(tasks).isZero();
        assertThat(items).isZero();
    }
```

- [ ] **Step 2: 컴파일 확인**

Run (in `server/`): `./gradlew compileTestJava`
Expected: BUILD SUCCESSFUL (테스트는 아직 실행하지 않는다 — Testcontainers는 CI에서 돈다. 엔드포인트가 없으므로 CI에서는 실패할 상태다.)

- [ ] **Step 3: 구현**

`TripSummaryResponse.java` 생성:
```java
package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;

import java.time.LocalDate;

// 여행 목록(GET /api/trips) 응답의 한 줄이다. 상세 응답(TripResponse)과 달리 준비 일정·여권 정보를
// 빼고 목록 카드에 필요한 값만 담는다 — 목록을 그릴 때마다 여행마다 trip_task를 조회하지 않기 위해서다.
// record: 필드·생성자·getter·equals를 자동으로 만들어 주는 Java의 불변 데이터 클래스다. 컨트롤러가
// 이 객체를 반환하면 Jackson이 필드 이름을 그대로 JSON 키로 써서 직렬화한다(LocalDate는 "yyyy-MM-dd").
public record TripSummaryResponse(
        Long id,
        String countryIso2,
        String countryNameKo,
        LocalDate departDate,
        LocalDate returnDate,
        // 여행 생성(또는 새로고침) 시점에 trip 테이블에 굳혀 둔 판정 스냅샷 값이다 — 목록에서도
        // 재계산하지 않는다(V4__trip.sql 상단 주석과 같은 이유).
        String verdict
) {
    public static TripSummaryResponse of(Trip trip, Country country) {
        return new TripSummaryResponse(
                trip.getId(),
                country.getIsoAlpha2(),
                country.getNameKo(),
                trip.getDepartDate(),
                trip.getReturnDate(),
                trip.getVerdict()
        );
    }
}
```

`TripRepository.java` 전체를 다음으로 교체:
```java
package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TripRepository extends JpaRepository<Trip, Long> {

    // Spring Data JPA는 메서드 이름을 해석해 쿼리를 자동으로 만든다(쿼리 메서드). 이 이름은
    // "WHERE firebase_uid = ? ORDER BY depart_date DESC"가 된다 — 구현 클래스를 직접 쓰지 않아도
    // 스프링이 실행 시점에 프록시 구현체를 만들어 빈으로 등록한다.
    List<Trip> findByFirebaseUidOrderByDepartDateDesc(String firebaseUid);
}
```

`TripController.java`:

1. import 추가:
```java
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
```
2. `create()` 메서드 바로 위에 `list()` 추가:
```java
    // GET /api/trips — 로그인한 사용자의 여행 목록(출발일 최신순). Authentication은 FirebaseAuthFilter가
    // 컨트롤러보다 먼저 실행되며 SecurityContext에 넣어 둔 인증 정보이고, getName()이 Firebase uid다.
    // 여행마다 국가를 하나씩 조회하면(N+1 쿼리) 목록이 길수록 느려지므로, 필요한 국가 id를 모아
    // findAllById로 한 번에 가져온 뒤 Map으로 붙인다.
    @GetMapping
    public List<TripSummaryResponse> list(Authentication authentication) {
        List<Trip> trips = tripRepository.findByFirebaseUidOrderByDepartDateDesc(authentication.getName());
        Map<Long, Country> countries = countryRepository
                .findAllById(trips.stream().map(Trip::getCountryId).distinct().toList())
                .stream()
                .collect(Collectors.toMap(Country::getId, Function.identity()));
        return trips.stream()
                .map(trip -> TripSummaryResponse.of(trip, countries.get(trip.getCountryId())))
                .toList();
    }
```
3. `checkChecklistItem()` 메서드 바로 아래에 `delete()` 추가:
```java
    // DELETE /api/trips/{id} — 여행을 지운다. @ResponseStatus(NO_CONTENT): 반환 본문이 없을 때
    // 기본값인 200 대신 204 No Content로 응답하라는 뜻이다.
    // trip_task·trip_checklist는 JPA 연관관계로 묶여 있지 않고 trip_id 숫자만 들고 있지만, DB의
    // 외래 키에 ON DELETE CASCADE가 걸려 있어(V4, V8 마이그레이션) trip 행 하나만 지우면 DB가 함께 지운다.
    // 남의 여행이면 findOwnedTripOrThrow가 404를 던진다 — 존재 여부를 감추는 규칙은 조회와 같다.
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id, Authentication authentication) {
        Trip trip = findOwnedTripOrThrow(id, authentication.getName());
        tripRepository.delete(trip);
    }
```
(`org.springframework.web.bind.annotation.*`가 이미 import되어 있어 `@DeleteMapping`·`@ResponseStatus`는 추가 import가 필요 없다.)

- [ ] **Step 4: 컴파일·단위 테스트 확인**

Run (in `server/`): `./gradlew compileJava compileTestJava`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/trip/TripSummaryResponse.java server/src/main/java/com/travelfootsteps/trip/TripRepository.java server/src/main/java/com/travelfootsteps/trip/TripController.java server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java
git commit -m "feat(server): 내 여행 목록 조회와 여행 삭제 API 추가"
```

---

### Task 2: 앱 — 여행 요약·여행 체크리스트 모델과 TripApi 확장

**Files:**
- Create: `app/lib/features/visa/models/trip_summary.dart`
- Create: `app/lib/features/visa/models/trip_checklist_item.dart`
- Modify: `app/lib/features/visa/data/trip_api.dart`
- Modify: `app/lib/features/visa/visa_result_display.dart`
- Modify: `app/test/visa/fake_trip_api.dart`
- Test: `app/test/visa/trip_api_test.dart`, `app/test/visa/trip_summary_test.dart`, `app/test/visa/visa_result_display_test.dart`

**Interfaces:**
- Produces:
  - `class TripSummary {int id; String countryIso2; String countryNameKo; DateTime departDate; DateTime returnDate; VisaVerdict verdict; factory fromJson(Map); Map<String,dynamic> toJson(); String get dateRangeLabel /* 'M/d~M/d' */}`
  - `class TripChecklistItem extends ChecklistItem {bool checked; factory fromJson(Map)}`
  - `TripApi.listTrips() → Future<List<TripSummary>>`, `TripApi.deleteTrip(int id) → Future<void>`, `TripApi.getChecklist(int tripId) → Future<List<TripChecklistItem>>`, `TripApi.checkItem(int tripId, int itemId, {required bool checked}) → Future<TripChecklistItem>`
  - `({String label, BadgeTone tone}) verdictChipOf(VisaVerdict verdict)` in `visa_result_display.dart`
  - test helpers: `sampleSummary({int id, String iso2, String nameKo, DateTime? depart, DateTime? ret, VisaVerdict verdict})`, `FakeTripApi({..., List<TripSummary> trips, int? listTripsStatusCode, int? deleteTripStatusCode, List<TripChecklistItem> checklist, int? getChecklistStatusCode, int? checkItemStatusCode})` with call logs `listTripsCalls`(int), `deleteTripCalls`(List<int>), `getChecklistCalls`(List<int>), `checkItemCalls`(List<({int tripId, int itemId, bool checked})>)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/visa/trip_summary_test.dart` 생성:
```dart
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 JSON을 파싱하고 toJson으로 되돌리면 같은 값이 된다', () {
    final json = {
      'id': 3,
      'countryIso2': 'JP',
      'countryNameKo': '일본',
      'departDate': '2026-11-03',
      'returnDate': '2026-11-08',
      'verdict': 'VISA_FREE_OK',
    };

    final summary = TripSummary.fromJson(json);

    expect(summary.id, 3);
    expect(summary.countryNameKo, '일본');
    expect(summary.departDate, DateTime(2026, 11, 3));
    expect(summary.verdict, VisaVerdict.visaFreeOk);
    expect(summary.toJson(), json);
  });

  test('날짜 범위 라벨은 M/d~M/d 형식이다', () {
    final summary = TripSummary(
      id: 1,
      countryIso2: 'VN',
      countryNameKo: '베트남',
      departDate: DateTime(2026, 12, 20),
      returnDate: DateTime(2027, 1, 9),
      verdict: VisaVerdict.visaRequired,
    );

    expect(summary.dateRangeLabel, '12/20~1/9');
  });
}
```

`app/test/visa/trip_api_test.dart` — `main()` 끝(마지막 `}` 앞)에 추가:
```dart
  test('listTrips가 GET /api/trips 목록을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips',
      statusCode: 200,
      body: '[{"id":3,"countryIso2":"JP","countryNameKo":"일본",'
          '"departDate":"2026-11-03","returnDate":"2026-11-08","verdict":"VISA_REQUIRED"}]',
    );

    final trips = await _apiReturning(adapter).listTrips();

    expect(adapter.lastRequest!.method, 'GET');
    expect(trips.single.id, 3);
    expect(trips.single.verdict, VisaVerdict.visaRequired);
  });

  test('deleteTrip이 DELETE /api/trips/{id}를 보낸다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/trips/3', statusCode: 204, body: '');

    await _apiReturning(adapter).deleteTrip(3);

    expect(adapter.lastRequest!.method, 'DELETE');
    expect(adapter.lastRequest!.path, '/api/trips/3');
  });

  test('getChecklist가 여행 체크리스트를 체크 여부와 함께 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/3/checklist',
      statusCode: 200,
      body: '[{"id":11,"category":"DOCUMENT","title":"여권","description":null,'
          '"priority":1,"checked":true}]',
    );

    final items = await _apiReturning(adapter).getChecklist(3);

    expect(items.single.id, 11);
    expect(items.single.categoryLabelKo, '서류');
    expect(items.single.checked, isTrue);
  });

  test('checkItem이 checked 값을 POST하고 바뀐 항목을 돌려준다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/3/checklist/11/check',
      statusCode: 200,
      body: '{"id":11,"category":"DOCUMENT","title":"여권","description":null,'
          '"priority":1,"checked":false}',
    );

    final item = await _apiReturning(adapter).checkItem(3, 11, checked: false);

    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.data, {'checked': false});
    expect(item.checked, isFalse);
  });
```

`app/test/visa/visa_result_display_test.dart` — `main()` 끝에 추가:
```dart
  test('목록용 판정 배지는 판정 종류만 짧게 말한다', () {
    expect(verdictChipOf(VisaVerdict.visaFreeOk), (label: '무비자', tone: BadgeTone.info));
    expect(verdictChipOf(VisaVerdict.visaFreeExceeded), (label: '무비자 초과', tone: BadgeTone.warn));
    expect(verdictChipOf(VisaVerdict.visaRequired), (label: '비자 필요', tone: BadgeTone.warn));
    expect(verdictChipOf(VisaVerdict.unverified), (label: '확인 필요', tone: BadgeTone.neutral));
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/visa/trip_summary_test.dart test/visa/trip_api_test.dart test/visa/visa_result_display_test.dart`
Expected: FAIL — `trip_summary.dart` 없음, `listTrips`/`verdictChipOf` 정의 없음

- [ ] **Step 3: 구현**

`app/lib/features/visa/models/trip_summary.dart` 생성:
```dart
import 'package:intl/intl.dart';

import 'trip.dart';

final _wireDate = DateFormat('yyyy-MM-dd');
final _shortDate = DateFormat('M/d');

/// 여행 목록(`GET /api/trips`)의 한 줄. 서버 `trip/TripSummaryResponse.java`와 필드명이 같다.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.countryIso2,
    required this.countryNameKo,
    required this.departDate,
    required this.returnDate,
    required this.verdict,
  });

  final int id;
  final String countryIso2;
  final String countryNameKo;
  final DateTime departDate;
  final DateTime returnDate;
  final VisaVerdict verdict;

  /// 목록 카드·준비물 탭 상단에 쓰는 `12/20~1/9` 형식.
  String get dateRangeLabel =>
      '${_shortDate.format(departDate)}~${_shortDate.format(returnDate)}';

  factory TripSummary.fromJson(Map<String, dynamic> json) => TripSummary(
        id: json['id'] as int,
        countryIso2: json['countryIso2'] as String,
        countryNameKo: json['countryNameKo'] as String,
        departDate: DateTime.parse(json['departDate'] as String),
        returnDate: DateTime.parse(json['returnDate'] as String),
        verdict: VisaVerdict.fromWire(json['verdict'] as String),
      );

  /// 목록 캐시(SharedPreferences)에 저장할 때 쓴다. [TripSummary.fromJson]으로 그대로 되읽힌다.
  Map<String, dynamic> toJson() => {
        'id': id,
        'countryIso2': countryIso2,
        'countryNameKo': countryNameKo,
        'departDate': _wireDate.format(departDate),
        'returnDate': _wireDate.format(returnDate),
        'verdict': verdict.wireValue,
      };
}
```

`app/lib/features/visa/models/trip_checklist_item.dart` 생성:
```dart
import '../../../core/network/checklist_api.dart';

/// 여행 한 건의 준비물 항목(서버 `trip/TripChecklistItemResponse.java`). 국가 공통 준비물
/// [ChecklistItem]과 모양이 같고 체크 여부만 더 가진다 — 그래서 준비물 화면의 섹션 묶기와
/// 보조배터리 행 끼워 넣기(`withPowerBankItem`)를 그대로 쓴다.
class TripChecklistItem extends ChecklistItem {
  const TripChecklistItem({
    required super.id,
    required super.category,
    required super.title,
    super.description,
    required super.priority,
    required this.checked,
  });

  final bool checked;

  factory TripChecklistItem.fromJson(Map<String, dynamic> json) => TripChecklistItem(
        id: json['id'] as int,
        category: json['category'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        priority: json['priority'] as int,
        checked: json['checked'] as bool,
      );
}
```

`app/lib/features/visa/data/trip_api.dart`:
- import 추가:
```dart
import '../models/trip_checklist_item.dart';
import '../models/trip_summary.dart';
```
- `markTaskDone` 메서드 아래(클래스 닫는 `}` 앞)에 추가:
```dart

  /// 내 여행 목록(출발일 최신순).
  Future<List<TripSummary>> listTrips() async {
    final response = await _dio.get<List<dynamic>>('/api/trips');
    return response.data!
        .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 여행을 지운다. 서버가 준비 일정·체크리스트도 함께 지운다.
  Future<void> deleteTrip(int id) async {
    await _dio.delete<void>('/api/trips/$id');
  }

  /// 여행 생성 시점에 복사해 둔 그 여행 전용 준비물 목록(우선순위순).
  Future<List<TripChecklistItem>> getChecklist(int tripId) async {
    final response = await _dio.get<List<dynamic>>('/api/trips/$tripId/checklist');
    return response.data!
        .map((e) => TripChecklistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 준비물 하나를 체크(또는 해제)한다.
  Future<TripChecklistItem> checkItem(int tripId, int itemId, {required bool checked}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trips/$tripId/checklist/$itemId/check',
      data: {'checked': checked},
    );
    return TripChecklistItem.fromJson(response.data!);
  }
```

`app/lib/features/visa/visa_result_display.dart` — 파일 끝에 추가:
```dart

/// 여행 목록 카드의 짧은 판정 배지. 목록 요약에는 허용 일수가 없어 판정 종류만 말한다.
({String label, BadgeTone tone}) verdictChipOf(VisaVerdict verdict) => switch (verdict) {
      VisaVerdict.visaFreeOk => (label: '무비자', tone: BadgeTone.info),
      VisaVerdict.visaFreeExceeded => (label: '무비자 초과', tone: BadgeTone.warn),
      VisaVerdict.visaRequired => (label: '비자 필요', tone: BadgeTone.warn),
      VisaVerdict.unverified => (label: '확인 필요', tone: BadgeTone.neutral),
    };
```

`app/test/visa/fake_trip_api.dart` — 전체를 다음으로 교체:
```dart
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/models/trip_checklist_item.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:dio/dio.dart';

/// 테스트용 샘플 여행. 필요한 값만 바꿔 쓴다.
Trip sampleTrip({
  int id = 7,
  String iso2 = 'VN',
  String nameKo = '베트남',
  VisaResult? visaResult,
  List<TripTask> tasks = const [],
  bool judgementStale = false,
}) {
  return Trip(
    id: id,
    countryIso2: iso2,
    countryNameKo: nameKo,
    departDate: DateTime(2026, 12, 20),
    returnDate: DateTime(2027, 1, 9),
    passportExpiry: DateTime(2027, 3, 15),
    visaResult: visaResult ??
        const VisaResult(
          verdict: VisaVerdict.visaFreeOk,
          stayDays: 20,
          visaFreeDays: 45,
          passportOk: true,
          passportValidityMonths: 6,
        ),
    tasks: tasks,
    judgementStale: judgementStale,
  );
}

/// 테스트용 여행 요약. 날짜를 주지 않으면 2026-12-20~2027-01-09.
TripSummary sampleSummary({
  int id = 7,
  String iso2 = 'VN',
  String nameKo = '베트남',
  DateTime? depart,
  DateTime? ret,
  VisaVerdict verdict = VisaVerdict.visaFreeOk,
}) {
  return TripSummary(
    id: id,
    countryIso2: iso2,
    countryNameKo: nameKo,
    departDate: depart ?? DateTime(2026, 12, 20),
    returnDate: ret ?? DateTime(2027, 1, 9),
    verdict: verdict,
  );
}

/// 서버 없이 TripApi를 쓰는 화면·provider를 테스트하기 위한 가짜 구현.
/// 호출 인자를 기록하고, 상태 코드를 지정하면 그 코드의 DioException을 던진다.
class FakeTripApi implements TripApi {
  FakeTripApi({
    Trip? tripToReturn,
    this.tripAfterRefresh,
    this.createTripStatusCode,
    this.getTripStatusCode,
    this.trips = const [],
    this.listTripsStatusCode,
    this.deleteTripStatusCode,
    this.checklist = const [],
    this.getChecklistStatusCode,
    this.checkItemStatusCode,
  }) : tripToReturn = tripToReturn ?? sampleTrip();

  final Trip tripToReturn;

  /// refreshTrip이 돌려줄 여행. 지정하지 않으면 [tripToReturn]을 그대로 준다.
  final Trip? tripAfterRefresh;

  final int? createTripStatusCode;
  final int? getTripStatusCode;
  final List<TripSummary> trips;
  final int? listTripsStatusCode;
  final int? deleteTripStatusCode;
  final List<TripChecklistItem> checklist;
  final int? getChecklistStatusCode;
  final int? checkItemStatusCode;

  final List<Map<String, Object>> createTripCalls = [];
  final List<int> getTripCalls = [];
  final List<int> refreshTripCalls = [];
  final List<({int tripId, int taskId})> markTaskDoneCalls = [];
  int listTripsCalls = 0;
  final List<int> deleteTripCalls = [];
  final List<int> getChecklistCalls = [];
  final List<({int tripId, int itemId, bool checked})> checkItemCalls = [];

  @override
  Future<Trip> createTrip({
    required String countryIso2,
    required DateTime departDate,
    required DateTime returnDate,
    required DateTime passportExpiry,
  }) async {
    createTripCalls.add({
      'countryIso2': countryIso2,
      'departDate': departDate,
      'returnDate': returnDate,
      'passportExpiry': passportExpiry,
    });
    if (createTripStatusCode != null) {
      throw _error('/api/trips', createTripStatusCode!);
    }
    return tripToReturn;
  }

  @override
  Future<Trip> getTrip(int id) async {
    getTripCalls.add(id);
    if (getTripStatusCode != null) {
      throw _error('/api/trips/$id', getTripStatusCode!);
    }
    return tripToReturn;
  }

  @override
  Future<Trip> refreshTrip(int id) async {
    refreshTripCalls.add(id);
    return tripAfterRefresh ?? tripToReturn;
  }

  @override
  Future<TripTask> markTaskDone(int tripId, int taskId) async {
    markTaskDoneCalls.add((tripId: tripId, taskId: taskId));
    return tripToReturn.tasks.firstWhere((t) => t.id == taskId).copyWith(done: true);
  }

  @override
  Future<List<TripSummary>> listTrips() async {
    listTripsCalls++;
    if (listTripsStatusCode != null) {
      throw _error('/api/trips', listTripsStatusCode!);
    }
    return trips;
  }

  @override
  Future<void> deleteTrip(int id) async {
    deleteTripCalls.add(id);
    if (deleteTripStatusCode != null) {
      throw _error('/api/trips/$id', deleteTripStatusCode!);
    }
  }

  @override
  Future<List<TripChecklistItem>> getChecklist(int tripId) async {
    getChecklistCalls.add(tripId);
    if (getChecklistStatusCode != null) {
      throw _error('/api/trips/$tripId/checklist', getChecklistStatusCode!);
    }
    return checklist;
  }

  @override
  Future<TripChecklistItem> checkItem(int tripId, int itemId, {required bool checked}) async {
    checkItemCalls.add((tripId: tripId, itemId: itemId, checked: checked));
    if (checkItemStatusCode != null) {
      throw _error('/api/trips/$tripId/checklist/$itemId/check', checkItemStatusCode!);
    }
    final item = checklist.firstWhere((i) => i.id == itemId);
    return TripChecklistItem(
      id: item.id,
      category: item.category,
      title: item.title,
      description: item.description,
      priority: item.priority,
      checked: checked,
    );
  }

  DioException _error(String path, int statusCode) {
    final options = RequestOptions(path: path);
    return DioException.badResponse(
      statusCode: statusCode,
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: statusCode),
    );
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/visa/ && dart analyze`
Expected: 모두 PASS, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/visa/models/trip_summary.dart app/lib/features/visa/models/trip_checklist_item.dart app/lib/features/visa/data/trip_api.dart app/lib/features/visa/visa_result_display.dart app/test/visa/fake_trip_api.dart app/test/visa/trip_api_test.dart app/test/visa/trip_summary_test.dart app/test/visa/visa_result_display_test.dart
git commit -m "feat(app): 여행 목록·삭제·여행별 체크리스트 API 클라이언트 추가"
```

---

### Task 3: 앱 — 여행 목록 캐시·선택된 여행·기본 여행 규칙

**Files:**
- Create: `app/lib/features/visa/data/trip_list_providers.dart`
- Test: `app/test/visa/trip_list_providers_test.dart`

**Interfaces:**
- Consumes: `TripApi.listTrips/getTrip`, `TripSummary.toJson/fromJson` (Task 2), `sharedPreferencesProvider`, `tripApiProvider`
- Produces:
  - `class TripListCache {TripListCache(SharedPreferences); List<TripSummary>? read(); Future<void> write(List<TripSummary>)}`
  - `final tripListCacheProvider = Provider<TripListCache>`
  - `class TripListState {const TripListState({required List<TripSummary> trips, bool offline = false})}`
  - `final tripListProvider = FutureProvider<TripListState>`
  - `class SelectedTripIdNotifier extends Notifier<int?> {Future<void> set(int); Future<void> clear()}` / `final selectedTripIdProvider`
  - `({List<TripSummary> upcoming, List<TripSummary> past}) splitTrips(List<TripSummary> trips, DateTime now)`
  - `TripSummary? resolveSelectedTrip(List<TripSummary> trips, int? selectedId, DateTime now)`
  - `final tripProvider = FutureProvider.autoDispose.family<Trip, int>`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/visa/trip_list_providers_test.dart` 생성:
```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

Future<ProviderContainer> _container({
  Map<String, Object> stored = const {},
  TripApi? api,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (api != null) tripApiProvider.overrideWithValue(api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final now = DateTime(2026, 10, 11, 15);
  final pastOld = sampleSummary(id: 1, depart: DateTime(2026, 3, 1), ret: DateTime(2026, 3, 5));
  final pastRecent = sampleSummary(id: 2, depart: DateTime(2026, 9, 1), ret: DateTime(2026, 9, 5));
  final endsToday = sampleSummary(id: 3, depart: DateTime(2026, 10, 8), ret: DateTime(2026, 10, 11));
  final later = sampleSummary(id: 4, depart: DateTime(2027, 1, 1), ret: DateTime(2027, 1, 5));

  group('splitTrips', () {
    test('귀국일이 오늘 이후면 다가오는 여행(출발일 오름차순), 아니면 지난 여행(출발일 내림차순)', () {
      final split = splitTrips([pastOld, later, pastRecent, endsToday], now);

      expect(split.upcoming.map((t) => t.id), [3, 4]);
      expect(split.past.map((t) => t.id), [2, 1]);
    });
  });

  group('resolveSelectedTrip', () {
    test('저장된 선택 여행이 목록에 있으면 그 여행', () {
      expect(resolveSelectedTrip([pastOld, later], 1, now)?.id, 1);
    });

    test('선택 여행이 없거나 목록에 없으면 가장 가까운 다가오는 여행', () {
      expect(resolveSelectedTrip([pastRecent, later, endsToday], null, now)?.id, 3);
      expect(resolveSelectedTrip([pastRecent, later], 99, now)?.id, 4);
    });

    test('다가오는 여행이 없으면 가장 최근 지난 여행', () {
      expect(resolveSelectedTrip([pastOld, pastRecent], null, now)?.id, 2);
    });

    test('여행이 하나도 없으면 null', () {
      expect(resolveSelectedTrip(const [], 1, now), isNull);
    });
  });

  group('TripListCache', () {
    test('쓴 목록을 그대로 읽는다', () async {
      final container = await _container();
      final cache = container.read(tripListCacheProvider);

      await cache.write([pastOld, later]);

      expect(cache.read()!.map((t) => t.id), [1, 4]);
    });

    test('캐시가 없거나 깨졌으면 null', () async {
      expect((await _container()).read(tripListCacheProvider).read(), isNull);
      final broken = await _container(stored: {'trips.cache.v1': 'not json'});
      expect(broken.read(tripListCacheProvider).read(), isNull);
    });
  });

  group('tripListProvider', () {
    test('서버 목록을 돌려주고 캐시에 저장한다', () async {
      final container = await _container(api: FakeTripApi(trips: [later]));

      final state = await container.read(tripListProvider.future);

      expect(state.trips.map((t) => t.id), [4]);
      expect(state.offline, isFalse);
      expect(container.read(tripListCacheProvider).read()!.single.id, 4);
    });

    test('서버 조회가 실패하면 캐시를 오프라인 표시와 함께 돌려준다', () async {
      final container = await _container(api: FakeTripApi(listTripsStatusCode: 503));
      await container.read(tripListCacheProvider).write([pastRecent]);

      final state = await container.read(tripListProvider.future);

      expect(state.trips.single.id, 2);
      expect(state.offline, isTrue);
    });

    test('서버 조회가 실패하고 캐시도 없으면 오류를 낸다', () async {
      final container = await _container(api: FakeTripApi(listTripsStatusCode: 503));

      await expectLater(container.read(tripListProvider.future), throwsA(anything));
    });
  });

  group('selectedTripIdProvider', () {
    test('저장된 값으로 시작하고 set/clear가 저장값도 바꾼다', () async {
      final container = await _container(stored: {'selected_trip_id': 5});
      final prefs = container.read(sharedPreferencesProvider);

      expect(container.read(selectedTripIdProvider), 5);

      await container.read(selectedTripIdProvider.notifier).set(8);
      expect(container.read(selectedTripIdProvider), 8);
      expect(prefs.getInt('selected_trip_id'), 8);

      await container.read(selectedTripIdProvider.notifier).clear();
      expect(container.read(selectedTripIdProvider), isNull);
      expect(prefs.getInt('selected_trip_id'), isNull);
    });
  });

  test('tripProvider는 id로 서버에서 여행을 가져온다', () async {
    final api = FakeTripApi(tripToReturn: sampleTrip(id: 9));
    final container = await _container(api: api);

    final trip = await container.read(tripProvider(9).future);

    expect(trip.id, 9);
    expect(api.getTripCalls, [9]);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/visa/trip_list_providers_test.dart`
Expected: FAIL — `trip_list_providers.dart` 없음

- [ ] **Step 3: 구현**

`app/lib/features/visa/data/trip_list_providers.dart` 생성:
```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../models/trip.dart';
import '../models/trip_summary.dart';
import 'trip_api.dart';

const _cacheKey = 'trips.cache.v1';
const _selectedTripIdKey = 'selected_trip_id';

/// 마지막으로 서버에서 받은 여행 목록. 해외에서 데이터가 끊겨도 준비물 탭 상단과 지갑까지는
/// 들어갈 수 있게 하려는 용도다(여행계획 중심 설계 §4.2). 깨진 값이면 없는 것으로 본다.
class TripListCache {
  TripListCache(this._prefs);

  final SharedPreferences _prefs;

  List<TripSummary>? read() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TripSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(List<TripSummary> trips) async {
    await _prefs.setString(_cacheKey, jsonEncode([for (final t in trips) t.toJson()]));
  }
}

final tripListCacheProvider = Provider<TripListCache>(
  (ref) => TripListCache(ref.watch(sharedPreferencesProvider)),
);

class TripListState {
  const TripListState({required this.trips, this.offline = false});

  final List<TripSummary> trips;

  /// 서버 조회에 실패해 캐시된 목록을 보여주는 중이다.
  final bool offline;
}

/// 내 여행 목록. 서버 조회에 성공하면 캐시를 갱신하고, 실패하면 캐시를 오프라인 표시와 함께 돌려준다.
/// 캐시도 없으면 오류를 그대로 낸다. 여행을 만들거나 지운 뒤에는 invalidate한다.
final tripListProvider = FutureProvider<TripListState>((ref) async {
  final cache = ref.watch(tripListCacheProvider);
  try {
    final trips = await ref.watch(tripApiProvider).listTrips();
    await cache.write(trips);
    return TripListState(trips: trips);
  } catch (_) {
    final cached = cache.read();
    if (cached == null) rethrow;
    return TripListState(trips: cached, offline: true);
  }
});

/// 준비물 탭이 보여줄 여행의 id. 앱을 재시작해도 유지된다.
class SelectedTripIdNotifier extends Notifier<int?> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  int? build() => ref.watch(sharedPreferencesProvider).getInt(_selectedTripIdKey);

  Future<void> set(int tripId) async {
    state = tripId;
    await _prefs.setInt(_selectedTripIdKey, tripId);
  }

  Future<void> clear() async {
    state = null;
    await _prefs.remove(_selectedTripIdKey);
  }
}

final selectedTripIdProvider =
    NotifierProvider<SelectedTripIdNotifier, int?>(SelectedTripIdNotifier.new);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 다가오는 여행(귀국일이 오늘 이후, 출발일 오름차순)과 지난 여행(출발일 내림차순)으로 나눈다.
({List<TripSummary> upcoming, List<TripSummary> past}) splitTrips(
  List<TripSummary> trips,
  DateTime now,
) {
  final today = _dateOnly(now);
  bool isPast(TripSummary t) => _dateOnly(t.returnDate).isBefore(today);
  final upcoming = trips.where((t) => !isPast(t)).toList()
    ..sort((a, b) => a.departDate.compareTo(b.departDate));
  final past = trips.where(isPast).toList()
    ..sort((a, b) => b.departDate.compareTo(a.departDate));
  return (upcoming: upcoming, past: past);
}

/// 준비물 탭이 보여줄 여행(설계 §3.3): 저장된 선택 여행 → 가장 가까운 다가오는 여행
/// → 가장 최근 지난 여행 → 없으면 null.
TripSummary? resolveSelectedTrip(List<TripSummary> trips, int? selectedId, DateTime now) {
  for (final t in trips) {
    if (t.id == selectedId) return t;
  }
  final split = splitTrips(trips, now);
  if (split.upcoming.isNotEmpty) return split.upcoming.first;
  if (split.past.isNotEmpty) return split.past.first;
  return null;
}

/// 여행 상세(판정·준비 일정). 화면을 떠나면 버리고, 다시 들어오면 서버에서 새로 읽는다.
final tripProvider = FutureProvider.autoDispose.family<Trip, int>(
  (ref, id) => ref.watch(tripApiProvider).getTrip(id),
);
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/visa/trip_list_providers_test.dart && dart analyze`
Expected: PASS, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/visa/data/trip_list_providers.dart app/test/visa/trip_list_providers_test.dart
git commit -m "feat(app): 여행 목록 캐시와 선택된 여행 provider 추가"
```

---

### Task 4: 앱 — 준비물 탭을 선택된 여행 기반으로 재구성

**Files:**
- Create: `app/lib/features/checklist/data/power_bank_check_store.dart`
- Modify: `app/lib/features/checklist/data/checklist_providers.dart` (전체 교체)
- Delete: `app/lib/features/checklist/data/checklist_checked_store.dart`, `app/test/checklist/checklist_checked_store_test.dart`
- Modify: `app/lib/features/checklist/data/power_bank_item.dart` (주석)
- Modify: `app/lib/features/checklist/checklist_page.dart`
- Modify: `app/lib/router.dart` (`visaNew` 상수·라우트)
- Test: `app/test/checklist/power_bank_check_store_test.dart`, `app/test/checklist/checklist_page_test.dart` (전체 교체)

**Interfaces:**
- Consumes: `tripListProvider`, `TripListState`, `selectedTripIdProvider`, `resolveSelectedTrip`, `splitTrips` (Task 3); `TripSummary`, `TripChecklistItem`, `TripApi.getChecklist/checkItem` (Task 2)
- Produces:
  - `class PowerBankCheckStore {PowerBankCheckStore(SharedPreferences); bool isChecked(int tripId); Future<void> setChecked(int tripId, bool checked); Future<void> remove(int tripId)}`
  - `final powerBankCheckStoreProvider = Provider<PowerBankCheckStore>`
  - `final powerBankCheckedProvider = Provider.family<bool, int>`
  - `final tripChecklistProvider = FutureProvider.autoDispose.family<List<TripChecklistItem>, int>`
  - `AppRoutes.visaNew = '/visa/new'` (지금은 기존 `VisaPage` 폼으로 연결)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/checklist/power_bank_check_store_test.dart` 생성:
```dart
import 'package:app/features/checklist/data/power_bank_check_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('여행별로 보조배터리 체크를 저장하고 지운다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PowerBankCheckStore(await SharedPreferences.getInstance());

    expect(store.isChecked(1), isFalse);

    await store.setChecked(1, true);
    expect(store.isChecked(1), isTrue);
    expect(store.isChecked(2), isFalse);

    await store.remove(1);
    expect(store.isChecked(1), isFalse);
  });
}
```

`app/test/checklist/checklist_page_test.dart` 전체 교체:
```dart
import 'package:app/core/network/country_detail_api.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/checklist/checklist_page.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/visa/models/trip_checklist_item.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../visa/fake_trip_api.dart';

const _defaultItems = [
  TripChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10, checked: false),
  TripChecklistItem(id: 20, category: 'MONEY', title: '환전', priority: 80, checked: false),
];

final _today = DateUtils.dateOnly(DateTime.now());
final _upcomingVn = sampleSummary(
    id: 1, depart: _today.add(const Duration(days: 30)), ret: _today.add(const Duration(days: 35)));
final _pastJp = sampleSummary(
    id: 2,
    iso2: 'JP',
    nameKo: '일본',
    depart: _today.subtract(const Duration(days: 60)),
    ret: _today.subtract(const Duration(days: 55)));

Future<({FakeTripApi api, SharedPreferences prefs})> _pumpChecklist(
  WidgetTester tester, {
  List<TripSummary>? trips,
  bool offline = false,
  Map<String, Object> stored = const {},
  List<TripChecklistItem> items = _defaultItems,
  int? getChecklistStatusCode,
  int? checkItemStatusCode,
  int? powerBankWhLimit = 100,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final api = FakeTripApi(
    checklist: items,
    getChecklistStatusCode: getChecklistStatusCode,
    checkItemStatusCode: checkItemStatusCode,
  );
  final router = GoRouter(
    initialLocation: '/checklist',
    routes: [
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: ChecklistPage())),
      GoRoute(
        path: '/checklist/wallet',
        builder: (_, state) => Scaffold(body: Text('wallet ${state.uri.queryParameters['iso']}')),
      ),
      GoRoute(
        path: '/checklist/rate-alert',
        builder: (_, state) => Scaffold(body: Text('rate-alert ${state.uri.queryParameters['iso']}')),
      ),
      GoRoute(path: '/visa/new', builder: (_, _) => const Scaffold(body: Text('새 여행 폼'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tripApiProvider.overrideWithValue(api),
      tripListProvider.overrideWith(
          (ref) async => TripListState(trips: trips ?? [_upcomingVn, _pastJp], offline: offline)),
      countryDetailProvider.overrideWith((ref, iso) async => CountryDetail(
            isoAlpha2: iso,
            nameKo: iso == 'JP' ? '일본' : '베트남',
            plugTypes: 'A, C, G',
            voltageV: 220,
            currencyCode: iso == 'JP' ? 'JPY' : 'VND',
            cardAcceptance: 'LOW',
            powerBankWhLimit: powerBankWhLimit,
          )),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return (api: api, prefs: prefs);
}

void main() {
  testWidgets('여행이 없으면 안내와 만들기 버튼을 보여주고, 누르면 새 여행 폼으로 간다', (tester) async {
    await _pumpChecklist(tester, trips: const []);

    expect(find.text('여행계획을 먼저 만들어 주세요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('createTripButton')));
    await tester.pumpAndSettle();

    expect(find.text('새 여행 폼'), findsOneWidget);
  });

  testWidgets('선택한 여행이 없으면 가장 가까운 다가오는 여행의 체크리스트를 보여준다', (tester) async {
    final r = await _pumpChecklist(tester);

    expect(find.text('준비물 · 베트남'), findsOneWidget);
    expect(find.text(_upcomingVn.dateRangeLabel), findsOneWidget);
    expect(find.text('멀티어댑터'), findsOneWidget);
    expect(r.api.getChecklistCalls, [1]);
  });

  testWidgets('저장된 선택 여행이 있으면 그 여행을 보여준다', (tester) async {
    final r = await _pumpChecklist(tester, stored: {'selected_trip_id': 2});

    expect(find.text('준비물 · 일본'), findsOneWidget);
    expect(r.api.getChecklistCalls, [2]);
  });

  testWidgets('여행 바꾸기 시트에서 고르면 그 여행으로 바뀌고 선택이 저장된다', (tester) async {
    final r = await _pumpChecklist(tester);

    await tester.tap(find.byKey(const Key('changeTripButton')));
    await tester.pumpAndSettle();
    expect(find.text('다가오는 여행'), findsOneWidget);
    expect(find.text('지난 여행'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tripOption_2')));
    await tester.pumpAndSettle();

    expect(find.text('준비물 · 일본'), findsOneWidget);
    expect(r.prefs.getInt('selected_trip_id'), 2);
    expect(r.api.getChecklistCalls, [1, 2]);
  });

  testWidgets('서버 체크리스트의 체크 상태를 보여주고, 누르면 서버에 저장한다', (tester) async {
    final r = await _pumpChecklist(tester, items: const [
      TripChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10, checked: true),
      TripChecklistItem(id: 20, category: 'MONEY', title: '환전', priority: 80, checked: false),
    ]);

    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.text('환전').last);
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(r.api.checkItemCalls, [(tripId: 1, itemId: 20, checked: true)]);
  });

  testWidgets('체크 저장이 실패하면 되돌리고 안내한다', (tester) async {
    await _pumpChecklist(tester, checkItemStatusCode: 500);

    await tester.tap(find.text('멀티어댑터'));
    await tester.pumpAndSettle();

    expect(find.text('0 / 3'), findsOneWidget);
    expect(find.text('저장하지 못했습니다. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('보조배터리 행은 서버가 아니라 기기에 여행별로 체크를 저장한다', (tester) async {
    final r = await _pumpChecklist(tester);

    expect(find.text('보조배터리 기내 반입 (100Wh 이하)'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);

    await tester.tap(find.text('보조배터리 기내 반입 (100Wh 이하)'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(r.prefs.getBool('checklist_powerbank_1'), isTrue);
    expect(r.api.checkItemCalls, isEmpty);
  });

  testWidgets('지갑 카드는 선택된 여행 나라의 지갑으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('VND ›'), findsOneWidget);
    await tester.tap(find.byKey(const Key('walletCard')));
    await tester.pumpAndSettle();

    expect(find.text('wallet VN'), findsOneWidget);
  });

  testWidgets('환전 섹션 끝의 환율 알림 행은 선택된 여행 나라의 환율 알림으로 간다', (tester) async {
    await _pumpChecklist(tester);

    expect(find.text('0 / 3'), findsOneWidget); // 체크 항목 수에는 들어가지 않는다
    await tester.ensureVisible(find.byKey(const Key('rateAlertLink')));
    await tester.tap(find.byKey(const Key('rateAlertLink')));
    await tester.pumpAndSettle();

    expect(find.text('rate-alert VN'), findsOneWidget);
  });

  testWidgets('준비물이 하나도 없어도 환율 알림 행이 있다', (tester) async {
    await _pumpChecklist(tester, items: const [], powerBankWhLimit: null);

    expect(find.text('이 나라에 등록된 준비물이 아직 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('rateAlertLink')), findsOneWidget);
  });

  testWidgets('환전 섹션이 없는 나라는 끝에 환전 섹션을 만들어 링크를 둔다', (tester) async {
    await _pumpChecklist(tester, items: const [
      TripChecklistItem(id: 10, category: 'POWER', title: '멀티어댑터', priority: 10, checked: false),
    ]);

    expect(find.text('환전'), findsOneWidget); // 섹션 라벨
    expect(find.byKey(const Key('rateAlertLink')), findsOneWidget);
  });

  testWidgets('체크리스트를 불러오지 못하면 다시 시도할 수 있다', (tester) async {
    await _pumpChecklist(tester, getChecklistStatusCode: 503);

    expect(find.text('준비물 목록을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.byKey(const Key('checklistRetry')), findsOneWidget);
  });

  testWidgets('캐시된 목록을 보여주는 중이면 오프라인 안내를 띄운다', (tester) async {
    await _pumpChecklist(tester, offline: true);

    expect(find.byKey(const Key('offlineBanner')), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/checklist/`
Expected: FAIL — `power_bank_check_store.dart` 없음, 화면이 여전히 VN 고정

- [ ] **Step 3: 구현**

`app/lib/features/checklist/data/power_bank_check_store.dart` 생성:
```dart
import 'package:shared_preferences/shared_preferences.dart';

/// 보조배터리 행은 서버 준비물이 아니라 앱이 국가 정보로 만드는 행이라(power_bank_item.dart),
/// 체크 여부만 기기에 여행별로 저장한다. 나머지 준비물의 체크는 서버(trip_checklist)에 있다.
class PowerBankCheckStore {
  PowerBankCheckStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(int tripId) => 'checklist_powerbank_$tripId';

  bool isChecked(int tripId) => _prefs.getBool(_key(tripId)) ?? false;

  Future<void> setChecked(int tripId, bool checked) async {
    await _prefs.setBool(_key(tripId), checked);
  }

  /// 여행을 지울 때 함께 지운다.
  Future<void> remove(int tripId) async {
    await _prefs.remove(_key(tripId));
  }
}
```

`app/lib/features/checklist/data/checklist_providers.dart` 전체 교체:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../visa/data/trip_api.dart';
import '../../visa/models/trip_checklist_item.dart';
import 'power_bank_check_store.dart';

final powerBankCheckStoreProvider = Provider<PowerBankCheckStore>((ref) {
  return PowerBankCheckStore(ref.watch(sharedPreferencesProvider));
});

/// 여행 하나의 보조배터리 체크 여부. 토글한 뒤 invalidate해서 다시 읽는다.
final powerBankCheckedProvider = Provider.family<bool, int>((ref, tripId) {
  return ref.watch(powerBankCheckStoreProvider).isChecked(tripId);
});

/// 여행 하나의 서버 준비물 목록(체크 여부 포함). 화면을 떠나면 버리고 다시 들어오면 새로 읽는다.
final tripChecklistProvider =
    FutureProvider.autoDispose.family<List<TripChecklistItem>, int>((ref, tripId) {
  return ref.watch(tripApiProvider).getChecklist(tripId);
});
```

삭제:
```bash
git rm app/lib/features/checklist/data/checklist_checked_store.dart app/test/checklist/checklist_checked_store_test.dart
```

`app/lib/features/checklist/data/power_bank_item.dart` — 상단 주석 두 줄 교체:
```dart
/// 보조배터리 행의 예약 id. 서버 준비물 템플릿 id(양수)와 겹치지 않게 음수를 쓴다.
/// 체크 상태는 다른 준비물처럼 ChecklistCheckedStore에 이 id로 저장된다.
```
→
```dart
/// 보조배터리 행의 예약 id. 서버 준비물 id(양수)와 겹치지 않게 음수를 쓴다.
/// 체크 상태는 서버가 아니라 PowerBankCheckStore에 여행별로 저장된다.
```

`app/lib/router.dart`:
- `static const visaResult = '/visa/result';` 위에 추가:
```dart
  /// 새 여행계획 입력 폼.
  static const visaNew = '/visa/new';
```
- 라우트 목록의 `GoRoute(path: AppRoutes.visaResult, ...)` 위에 추가:
```dart
          GoRoute(path: AppRoutes.visaNew, builder: (_, _) => const VisaPage()),
```

`app/lib/features/checklist/checklist_page.dart` — 파일 처음부터 `class _Header`의 끝까지(즉 `class _InfoLoading extends StatelessWidget {` 바로 앞까지)를 아래로 교체한다. `class _InfoLoading` 이후(`_InfoLoading`, `_InfoError`, `_CountryInfoRow`, `_CountryInfoCard`, `_ProgressCard`, `_ChecklistRow`, `_CheckboxSquare`, `_RateAlertLink`, `_AddManuallyRow`)는 그대로 둔다.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/checklist_api.dart';
import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import '../visa/data/trip_api.dart';
import '../visa/data/trip_list_providers.dart';
import '../visa/models/trip_checklist_item.dart';
import '../visa/models/trip_summary.dart';
import 'data/checklist_providers.dart';
import 'data/power_bank_item.dart';

/// 준비물 · 짐/서류 체크리스트 화면.
///
/// 나라를 직접 고르지 않고 "선택된 여행"의 체크리스트를 보여준다(여행계획 중심 설계 §3.3).
/// 목록과 체크 상태는 그 여행의 서버 체크리스트(`trip_checklist`)이고, 앱이 만드는 보조배터리
/// 행의 체크만 기기에 여행별로 저장한다.
class ChecklistPage extends ConsumerWidget {
  const ChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(tripListProvider);
    final selectedId = ref.watch(selectedTripIdProvider);

    return listAsync.when(
      loading: () => const Column(
        children: [
          _Header(),
          Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      ),
      error: (e, _) => Column(
        children: [
          const _Header(),
          Expanded(
            child: _CenteredMessage(
              message: '여행 목록을 불러오지 못했습니다.',
              actionLabel: '다시 시도',
              onAction: () => ref.invalidate(tripListProvider),
            ),
          ),
        ],
      ),
      data: (state) {
        final trip = resolveSelectedTrip(state.trips, selectedId, DateTime.now());
        if (trip == null) {
          return Column(
            children: [
              const _Header(),
              Expanded(
                child: _CenteredMessage(
                  message: '여행계획을 먼저 만들어 주세요.',
                  actionLabel: '여행계획 만들기',
                  actionKey: const Key('createTripButton'),
                  onAction: () => context.go(AppRoutes.visaNew),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _Header(trip: trip, onChangeTrip: () => _pickTrip(context, ref, state.trips)),
            if (state.offline) const _OfflineBanner(),
            // 여행이 바뀌면 낙관적 체크 상태를 새로 시작해야 하므로 id를 key로 준다.
            Expanded(child: _TripChecklistBody(key: ValueKey(trip.id), trip: trip)),
          ],
        );
      },
    );
  }

  Future<void> _pickTrip(BuildContext context, WidgetRef ref, List<TripSummary> trips) async {
    final picked = await showModalBottomSheet<TripSummary>(
      context: context,
      builder: (_) => _TripPickerSheet(trips: trips),
    );
    if (picked != null) await ref.read(selectedTripIdProvider.notifier).set(picked.id);
  }
}

class _TripChecklistBody extends ConsumerStatefulWidget {
  const _TripChecklistBody({super.key, required this.trip});

  final TripSummary trip;

  @override
  ConsumerState<_TripChecklistBody> createState() => _TripChecklistBodyState();
}

class _TripChecklistBodyState extends ConsumerState<_TripChecklistBody> {
  /// 서버 저장을 기다리지 않고 화면에 먼저 반영한 체크 상태. 저장이 실패하면 지운다(되돌림).
  final Map<int, bool> _optimistic = {};

  TripSummary get _trip => widget.trip;

  @override
  Widget build(BuildContext context) {
    final iso = _trip.countryIso2;
    final detailAsync = ref.watch(countryDetailProvider(iso));
    final checklistAsync = ref.watch(tripChecklistProvider(_trip.id));
    final powerBankChecked = ref.watch(powerBankCheckedProvider(_trip.id));

    bool isChecked(ChecklistItem item) {
      if (item.id == powerBankChecklistId) return powerBankChecked;
      return _optimistic[item.id] ?? (item is TripChecklistItem && item.checked);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          detailAsync.when(
            data: (detail) => _CountryInfoRow(
              detail: detail,
              onOpenWallet: () => context.push(AppRoutes.walletOf(iso)),
            ),
            loading: () => const _InfoLoading(),
            error: (e, _) => _InfoError('국가 정보를 불러오지 못했습니다: $e'),
          ),
          const SizedBox(height: 14),
          checklistAsync.when(
            data: (serverItems) {
              // 보조배터리는 상단 카드에서 체크리스트 행으로 옮겼다(지갑·환율 알림 설계 §5.1).
              final items = withPowerBankItem(serverItems, detailAsync.value?.powerBankWhLimit);
              final checkedCount = items.where(isChecked).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProgressCard(total: items.length, checked: checkedCount),
                  const SizedBox(height: 14),
                  ..._buildSections(items, isChecked),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _InfoError('준비물 목록을 불러오지 못했습니다.'),
                TextButton(
                  key: const Key('checklistRetry'),
                  onPressed: () => ref.invalidate(tripChecklistProvider(_trip.id)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _AddManuallyRow(),
        ],
      ),
    );
  }

  /// 카테고리별로 묶어서 SectionLabel + 항목들을 순서대로 만든다.
  /// 서버가 priority 오름차순으로 이미 정렬해서 주므로, 처음 등장하는 순서 그대로
  /// 섹션을 나눈다. 환전(`MONEY`) 섹션 끝에는 환율 알림 설정으로 가는 행을 붙이고(지갑·환율 알림 설계 §6.1),
  /// 환전 섹션이 없는 나라면 목록 끝에 환전 섹션을 새로 만들어 그 행을 넣는다.
  List<Widget> _buildSections(List<ChecklistItem> items, bool Function(ChecklistItem) isChecked) {
    final widgets = <Widget>[];
    String? currentCategory;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.category != currentCategory) {
        currentCategory = item.category;
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
        widgets.add(SectionLabel(item.categoryLabelKo));
        widgets.add(const SizedBox(height: 4));
      }
      final checked = isChecked(item);
      widgets.add(_ChecklistRow(
        checked: checked,
        label: item.title,
        description: item.description,
        onTap: () => _toggle(item, checked),
      ));
      final lastOfMoney = item.category == _moneyCategory &&
          (i == items.length - 1 || items[i + 1].category != _moneyCategory);
      if (lastOfMoney) widgets.add(_RateAlertLink(onTap: _openRateAlert));
    }

    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('이 나라에 등록된 준비물이 아직 없습니다.'),
      ));
    }
    // 빈 목록 안내와 별개로, 환전 섹션이 없으면(빈 목록 포함) 끝에 만들어 환율 알림 진입 행을 둔다.
    if (!items.any((i) => i.category == _moneyCategory)) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
      widgets
        ..add(const SectionLabel('환전'))
        ..add(const SizedBox(height: 4))
        ..add(_RateAlertLink(onTap: _openRateAlert));
    }
    return widgets;
  }

  static const _moneyCategory = 'MONEY';

  void _openRateAlert() => context.push(AppRoutes.rateAlertOf(_trip.countryIso2));

  /// 보조배터리 행은 기기에 저장하고, 나머지는 화면에 먼저 반영한 뒤 서버에 저장한다.
  /// 서버 저장이 실패하면 화면을 되돌리고 알린다.
  Future<void> _toggle(ChecklistItem item, bool current) async {
    final next = !current;
    if (item.id == powerBankChecklistId) {
      await ref.read(powerBankCheckStoreProvider).setChecked(_trip.id, next);
      if (mounted) ref.invalidate(powerBankCheckedProvider(_trip.id));
      return;
    }
    setState(() => _optimistic[item.id] = next);
    try {
      await ref.read(tripApiProvider).checkItem(_trip.id, item.id, checked: next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimistic.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장하지 못했습니다. 다시 시도해 주세요.')),
      );
    }
  }
}

/// 상단 제목줄. 여행이 정해지면 나라·날짜와 [여행 바꾸기]를 보여준다.
class _Header extends StatelessWidget {
  const _Header({this.trip, this.onChangeTrip});

  final TripSummary? trip;
  final VoidCallback? onChangeTrip;

  @override
  Widget build(BuildContext context) {
    final trip = this.trip;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trip == null ? '준비물' : '준비물 · ${trip.countryNameKo}',
                  style: AppTextStyles.screenTitle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (trip != null) Text(trip.dateRangeLabel, style: AppTextStyles.caption),
              ],
            ),
          ),
          if (onChangeTrip != null)
            GestureDetector(
              key: const Key('changeTripButton'),
              onTap: onChangeTrip,
              child: Text(
                '여행 바꾸기',
                style: AppTextStyles.caption.copyWith(color: AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('offlineBanner'),
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Text('오프라인 · 마지막으로 불러온 목록', style: AppTextStyles.caption),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 20),
            TextButton(key: actionKey, onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// [여행 바꾸기] 시트. 나라가 아니라 내 여행 중에서 고른다.
class _TripPickerSheet extends StatelessWidget {
  const _TripPickerSheet({required this.trips});

  final List<TripSummary> trips;

  @override
  Widget build(BuildContext context) {
    final split = splitTrips(trips, DateTime.now());
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: ListView(
          children: [
            if (split.upcoming.isNotEmpty) ...[
              const _SheetSection('다가오는 여행'),
              for (final t in split.upcoming) _option(context, t),
            ],
            if (split.past.isNotEmpty) ...[
              const _SheetSection('지난 여행'),
              for (final t in split.past) _option(context, t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, TripSummary trip) => ListTile(
        key: Key('tripOption_${trip.id}'),
        title: Text(trip.countryNameKo),
        subtitle: Text(trip.dateRangeLabel),
        onTap: () => Navigator.of(context).pop(trip),
      );
}

class _SheetSection extends StatelessWidget {
  const _SheetSection(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: SectionLabel(text),
    );
  }
}
```

`_InfoError`가 `const` 생성자로 쓰이므로(위 코드의 `const _InfoError('준비물 목록을 불러오지 못했습니다.')`) 파일 아래쪽의 `class _InfoError`가 `const _InfoError(this.message);`인지 확인한다(이미 const다).

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/checklist/ && dart analyze`
Expected: PASS, `No issues found!`

- [ ] **Step 5: 커밋**

```bash
git add -A app/lib/features/checklist app/test/checklist app/lib/router.dart
git commit -m "feat(app): 준비물 탭이 선택된 여행의 서버 체크리스트를 보여준다"
```

---

### Task 5: 앱 — 지갑을 여행별(tripId)로 저장

**Files:**
- Modify: `app/lib/features/wallet/data/wallet_database.dart` (+ `wallet_database.g.dart` 재생성)
- Modify: `app/lib/features/wallet/wallet_page.dart`
- Modify: `app/lib/router.dart`
- Modify: `app/lib/features/checklist/checklist_page.dart` (지갑 링크 한 줄)
- Test: `app/test/wallet/wallet_database_test.dart`, `app/test/wallet/wallet_fixtures.dart`, `app/test/wallet/wallet_page_test.dart`, `app/test/checklist/checklist_page_test.dart`

**Interfaces:**
- Consumes: `TripSummary` (Task 2), Task 4의 `_TripChecklistBody`
- Produces:
  - `WalletDatabase.addExpense({required int tripId, ...})`, `addExchange({required int tripId, ...})`, `watchExpenses(int tripId)`, `watchExchanges(int tripId)`, `clearWallet(int tripId)`; `ExpenseRow.tripId`, `ExchangeRow.tripId` (int); `schemaVersion == 2`
  - `walletExpensesProvider`/`walletExchangesProvider`: `StreamProvider.family<..., int>`
  - `WalletPage({required int tripId, required String isoAlpha2})`
  - `AppRoutes.walletOf(int tripId, String isoAlpha2) → '/checklist/wallet?trip=<id>&iso=<iso>'`

- [ ] **Step 1: 테스트를 tripId 기준으로 고치기 (실패 상태로)**

`app/test/wallet/wallet_database_test.dart`에서:
- `isoAlpha2: 'JP'` → `tripId: 1`, `isoAlpha2: 'VN'` → `tripId: 2` (모든 호출)
- `watchExpenses('JP')`/`watchExchanges('JP')` → `watchExpenses(1)`/`watchExchanges(1)`, `watchExpenses('VN')` → `watchExpenses(2)`
- `db.clearWallet('JP')` → `db.clearWallet(1)`
- 테스트 이름: `'지출을 저장하면 그 나라 목록에 그대로 나온다'` → `'지출을 저장하면 그 여행 목록에 그대로 나온다'`, `'나라별로 나뉘고, 최근 날짜·나중 기록이 먼저 온다'` → `'여행별로 나뉘고, 최근 날짜·나중 기록이 먼저 온다'`, `'지갑 비우기는 그 나라의 지출·환전만 지운다'` → `'지갑 비우기는 그 여행의 지출·환전만 지운다'`
- 파일 끝(마지막 `}` 앞)에 추가:
```dart

  test('스키마 버전은 2다(기록 묶음 기준이 여행으로 바뀜)', () {
    expect(db.schemaVersion, 2);
  });
```

`app/test/wallet/wallet_fixtures.dart`에서 `expense()`와 `exchange()` 둘 다:
- 파라미터 `String iso = 'JP',` → `int tripId = 1,`
- 생성자 인자 `isoAlpha2: iso,` → `tripId: tripId,`

`app/test/wallet/wallet_page_test.dart`에서:
- `WalletPage(isoAlpha2: 'JP')` → `WalletPage(tripId: 1, isoAlpha2: 'JP')`
- `walletExpensesProvider.overrideWith((ref, iso) => ...)` / `walletExchangesProvider.overrideWith((ref, iso) => ...)`의 람다 인자 이름 `iso` → `tripId`

`app/test/checklist/checklist_page_test.dart`에서:
- 지갑 라우트 builder를 `Text('wallet ${state.uri.queryParameters['trip']} ${state.uri.queryParameters['iso']}')`로 바꾸고
- `expect(find.text('wallet VN'), findsOneWidget);` → `expect(find.text('wallet 1 VN'), findsOneWidget);`

Run: `flutter test test/wallet/ test/checklist/`
Expected: FAIL (컴파일 오류 — `tripId` 파라미터 없음)

- [ ] **Step 2: DB 구현**

`app/lib/features/wallet/data/wallet_database.dart`:
- `Expenses`와 `Exchanges` 둘 다 `TextColumn get isoAlpha2 => text()();`를 다음으로 교체:
```dart
  /// 이 기록이 속한 여행(서버 trip id). 같은 나라를 두 번 가도 가계부가 섞이지 않게 여행으로 묶는다.
  IntColumn get tripId => integer()();
```
- 클래스 doc의 `/// 지갑 전용 로컬 DB(...)` 블록은 그대로 두고, `schemaVersion`을 다음으로 교체:
```dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // 1→2: 기록 묶음 기준이 나라(isoAlpha2)에서 여행(tripId)으로 바뀌었다. 1단계 기록은 테스트
        // 데이터뿐이라 옮기지 않고 두 테이블을 다시 만든다(여행계획 중심 설계 §4.2).
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.deleteTable('expenses');
            await m.deleteTable('exchanges');
            await m.createAll();
          }
        },
      );
```
- `addExpense`/`addExchange`의 `required String isoAlpha2,` → `required int tripId,`, companion 인자 `isoAlpha2: isoAlpha2,` → `tripId: tripId,`
- `watchExpenses`/`watchExchanges`/`clearWallet` 교체:
```dart
  /// 한 여행의 지출. 최근 날짜 먼저, 같은 날은 나중에 넣은 것 먼저.
  Stream<List<ExpenseRow>> watchExpenses(int tripId) {
    return (select(expenses)
          ..where((e) => e.tripId.equals(tripId))
          ..orderBy([(e) => OrderingTerm.desc(e.spentOn), (e) => OrderingTerm.desc(e.id)]))
        .watch();
  }

  /// 한 여행의 환전. 정렬 규칙은 [watchExpenses]와 같다.
  Stream<List<ExchangeRow>> watchExchanges(int tripId) {
    return (select(exchanges)
          ..where((x) => x.tripId.equals(tripId))
          ..orderBy([(x) => OrderingTerm.desc(x.exchangedOn), (x) => OrderingTerm.desc(x.id)]))
        .watch();
  }

  /// 이 여행의 지갑 기록(지출·환전)을 모두 지운다. 다른 여행 기록은 그대로 둔다.
  Future<void> clearWallet(int tripId) {
    return transaction(() async {
      await (delete(expenses)..where((e) => e.tripId.equals(tripId))).go();
      await (delete(exchanges)..where((x) => x.tripId.equals(tripId))).go();
    });
  }
```
- 파일 끝 provider 두 개 교체:
```dart
/// 여행별 지출 목록. DB가 바뀌면 자동으로 다시 내보낸다.
final walletExpensesProvider =
    StreamProvider.family<List<ExpenseRow>, int>((ref, tripId) {
  return ref.watch(walletDatabaseProvider).watchExpenses(tripId);
});

/// 여행별 환전 목록.
final walletExchangesProvider =
    StreamProvider.family<List<ExchangeRow>, int>((ref, tripId) {
  return ref.watch(walletDatabaseProvider).watchExchanges(tripId);
});
```

코드 생성:
```bash
dart run build_runner build --force-jit --delete-conflicting-outputs
git checkout -- lib/core/db/app_database.g.dart
```
Expected: `lib/features/wallet/data/wallet_database.g.dart`만 바뀐다 (`git status`로 확인).

- [ ] **Step 3: 화면·라우트 구현**

`app/lib/features/wallet/wallet_page.dart`:
- 클래스 doc 교체:
```dart
/// 여행별 지갑(여행 가계부) 화면 — 지갑·환율 알림 설계 §5.2, 여행계획 중심 설계 §3.4.
/// 준비물 탭 `지갑` 카드나 여행 상세의 [지갑]에서 `/checklist/wallet?trip=3&iso=JP`로 들어온다.
/// 기록은 여행(tripId)별로 기기에만 저장하고, 통화는 나라(isoAlpha2)로 정한다.
```
- 생성자·필드:
```dart
  const WalletPage({super.key, required this.tripId, required this.isoAlpha2});

  final int tripId;
  final String isoAlpha2;
```
- `_wallet()`의 `final iso = widget.isoAlpha2;`와 그 아래 두 줄을:
```dart
    final tripId = widget.tripId;
    final rate = ref.watch(walletRateProvider(currency.code)).value;
    final expenses = ref.watch(walletExpensesProvider(tripId)).value ?? const <ExpenseRow>[];
    final exchanges = ref.watch(walletExchangesProvider(tripId)).value ?? const <ExchangeRow>[];
```
  (`rate` 줄은 원래 있던 그대로다 — `iso` 변수가 다른 곳에서 쓰이면 `widget.isoAlpha2`로 바꾼다.)
- `_addExpense`/`_addExchange`의 `isoAlpha2: widget.isoAlpha2,` → `tripId: widget.tripId,`
- `_clear`의 `await _db.clearWallet(widget.isoAlpha2);` → `await _db.clearWallet(widget.tripId);`

`app/lib/router.dart`:
- 지갑 상수 doc·`walletOf` 교체:
```dart
  /// 여행별 지갑. 준비물 탭 아래 화면이라 경로를 /checklist로 시작해 탭바의 준비물 탭이 켜진 채로 둔다.
  static const wallet = '/checklist/wallet';

  static String walletOf(int tripId, String isoAlpha2) => '$wallet?trip=$tripId&iso=$isoAlpha2';
```
- 지갑 GoRoute builder 교체:
```dart
            builder: (_, state) => WalletPage(
              tripId: int.tryParse(state.uri.queryParameters['trip'] ?? '') ?? 0,
              isoAlpha2: state.uri.queryParameters['iso'] ?? 'VN',
            ),
```

`app/lib/features/checklist/checklist_page.dart`의 `_TripChecklistBodyState.build`:
```dart
              onOpenWallet: () => context.push(AppRoutes.walletOf(iso)),
```
→
```dart
              onOpenWallet: () => context.push(AppRoutes.walletOf(_trip.id, iso)),
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/wallet/ test/checklist/ && dart analyze`
Expected: PASS, `No issues found!` (`grep -rn "walletOf\|isoAlpha2:" lib/features/wallet`로 남은 나라 기준 호출이 없는지 확인)

- [ ] **Step 5: 커밋**

```bash
git add app/lib/features/wallet app/lib/router.dart app/lib/features/checklist/checklist_page.dart app/test/wallet app/test/checklist/checklist_page_test.dart
git commit -m "feat(app): 지갑 기록을 나라 대신 여행별로 저장한다"
```

---

### Task 6: 앱 — 여행 탭(목록·새 여행·상세·삭제)

**Files:**
- Create: `app/lib/features/visa/trip_list_page.dart`
- Create: `app/lib/features/visa/data/trip_deletion.dart`
- Modify: `app/lib/features/visa/visa_page.dart`
- Modify: `app/lib/features/visa/visa_result_page.dart`
- Delete: `app/lib/features/visa/data/trip_providers.dart`, `app/test/visa/trip_providers_test.dart`
- Modify: `app/lib/router.dart`
- Test: `app/test/visa/trip_list_page_test.dart`, `app/test/visa/trip_deletion_test.dart`, `app/test/visa/visa_result_page_test.dart`, `app/test/visa/visa_page_test.dart`, `app/test/router_test.dart`

**Interfaces:**
- Consumes: `tripListProvider`, `TripListState`, `selectedTripIdProvider`, `splitTrips`, `tripProvider` (Task 3); `TripSummary`, `verdictChipOf`, `TripApi.deleteTrip` (Task 2); `powerBankCheckStoreProvider` (Task 4); `walletDatabaseProvider`, `AppRoutes.walletOf(int, String)` (Task 5); `AppRoutes.visaNew` (Task 4)
- Produces:
  - `class TripDeleter {TripDeleter(this.ref); final Ref ref; Future<void> delete(int tripId)}` / `final tripDeleterProvider = Provider<TripDeleter>`
  - `TripListPage()`, `VisaResultPage({required int tripId})`
  - `AppRoutes.tripDetail = '/visa/trip/:id'`, `AppRoutes.tripOf(int id)`; `AppRoutes.visaResult` 제거; `tabLabels[0] == '여행'`

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/visa/trip_deletion_test.dart` 생성:
```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_deletion.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

Future<({ProviderContainer container, WalletDatabase db, SharedPreferences prefs})> _setUp(
    FakeTripApi api) async {
  SharedPreferences.setMockInitialValues({
    'selected_trip_id': 7,
    'checklist_powerbank_7': true,
    'checklist_powerbank_8': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = WalletDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    tripApiProvider.overrideWithValue(api),
    walletDatabaseProvider.overrideWithValue(db),
  ]);
  addTearDown(container.dispose);
  for (final tripId in [7, 8]) {
    await db.addExpense(tripId: tripId, currencyCode: 'VND', category: 'FOOD',
        amountMinor: 50000, spentOn: DateTime(2026, 12, 21));
  }
  return (container: container, db: db, prefs: prefs);
}

void main() {
  test('서버에서 지운 뒤 그 여행의 지갑·보조배터리 체크·선택을 정리한다', () async {
    final api = FakeTripApi();
    final s = await _setUp(api);
    expect(s.container.read(selectedTripIdProvider), 7);

    await s.container.read(tripDeleterProvider).delete(7);

    expect(api.deleteTripCalls, [7]);
    expect(await s.db.watchExpenses(7).first, isEmpty);
    expect(await s.db.watchExpenses(8).first, hasLength(1));
    expect(s.prefs.getBool('checklist_powerbank_7'), isNull);
    expect(s.prefs.getBool('checklist_powerbank_8'), isTrue);
    expect(s.container.read(selectedTripIdProvider), isNull);
  });

  test('선택된 여행이 아니면 선택은 그대로 둔다', () async {
    final s = await _setUp(FakeTripApi());

    await s.container.read(tripDeleterProvider).delete(8);

    expect(s.container.read(selectedTripIdProvider), 7);
  });

  test('서버 삭제가 실패하면 기기 쪽은 아무것도 지우지 않는다', () async {
    final s = await _setUp(FakeTripApi(deleteTripStatusCode: 500));

    await expectLater(s.container.read(tripDeleterProvider).delete(7), throwsA(anything));

    expect(await s.db.watchExpenses(7).first, hasLength(1));
    expect(s.prefs.getBool('checklist_powerbank_7'), isTrue);
    expect(s.container.read(selectedTripIdProvider), 7);
  });
}
```

`app/test/visa/trip_list_page_test.dart` 생성:
```dart
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:app/features/visa/trip_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_trip_api.dart';

final _today = DateUtils.dateOnly(DateTime.now());

Future<void> _pumpList(
  WidgetTester tester, {
  List<TripSummary> trips = const [],
  bool offline = false,
  bool fails = false,
}) async {
  final router = GoRouter(
    initialLocation: '/visa',
    routes: [
      GoRoute(path: '/visa', builder: (_, _) => const Scaffold(body: TripListPage())),
      GoRoute(path: '/visa/new', builder: (_, _) => const Scaffold(body: Text('새 여행 폼'))),
      GoRoute(
        path: '/visa/trip/:id',
        builder: (_, state) => Scaffold(body: Text('상세 ${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      tripListProvider.overrideWith((ref) async {
        if (fails) throw Exception('offline');
        return TripListState(trips: trips, offline: offline);
      }),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('여행이 없으면 첫 여행을 만들라고 안내하고, 누르면 새 여행 폼으로 간다', (tester) async {
    await _pumpList(tester);

    expect(find.text('첫 여행계획을 만들어 보세요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('emptyCreateTripButton')));
    await tester.pumpAndSettle();

    expect(find.text('새 여행 폼'), findsOneWidget);
  });

  testWidgets('다가오는 여행과 지난 여행을 나눠 보여주고, 카드를 누르면 상세로 간다', (tester) async {
    await _pumpList(tester, trips: [
      sampleSummary(
          id: 1,
          iso2: 'JP',
          nameKo: '일본',
          depart: _today.subtract(const Duration(days: 60)),
          ret: _today.subtract(const Duration(days: 55))),
      sampleSummary(
          id: 2,
          depart: _today.add(const Duration(days: 30)),
          ret: _today.add(const Duration(days: 35))),
    ]);

    expect(find.text('다가오는 여행'), findsOneWidget);
    expect(find.text('지난 여행'), findsOneWidget);
    expect(find.text('일본'), findsOneWidget);
    expect(find.text('베트남'), findsOneWidget);
    expect(find.text('무비자'), findsNWidgets(2));
    final upcomingY = tester.getTopLeft(find.text('베트남')).dy;
    final pastY = tester.getTopLeft(find.text('일본')).dy;
    expect(upcomingY, lessThan(pastY));

    await tester.tap(find.text('베트남'));
    await tester.pumpAndSettle();

    expect(find.text('상세 2'), findsOneWidget);
  });

  testWidgets('상단 버튼으로 새 여행 폼에 간다', (tester) async {
    await _pumpList(tester, trips: [sampleSummary()]);

    await tester.tap(find.byKey(const Key('createTripButton')));
    await tester.pumpAndSettle();

    expect(find.text('새 여행 폼'), findsOneWidget);
  });

  testWidgets('캐시된 목록이면 오프라인 안내를 보여준다', (tester) async {
    await _pumpList(tester, trips: [sampleSummary()], offline: true);

    expect(find.text('오프라인 · 마지막으로 불러온 목록'), findsOneWidget);
  });

  testWidgets('목록을 불러오지 못하면 다시 시도할 수 있다', (tester) async {
    await _pumpList(tester, fails: true);

    expect(find.text('여행 목록을 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
```

`app/test/visa/visa_result_page_test.dart` — import부터 `pumpResultPage` 끝까지와 첫 테스트(`'저장한 여행이 없으면 안내를 보여준다'`)를 교체한다. 나머지 기존 테스트(`'국가 이름과 판정 결과를 서버 데이터로 보여준다'` ~ `'폰 폭(360)에서...'`)는 그대로 둔다(`pumpResultPage(tester, trip: ...)` 호출 모양이 같다).

파일 맨 위~`void main() {` 다음 첫 테스트까지를 다음으로 교체:
```dart
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_deletion.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/visa_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

class _FakeTripDeleter implements TripDeleter {
  _FakeTripDeleter({this.fails = false});

  final bool fails;
  final List<int> calls = [];

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> delete(int tripId) async {
    calls.add(tripId);
    if (fails) throw Exception('delete failed');
  }
}

/// 여행 상세 화면을 `/visa/trip/:id`로 띄운다. 화면이 목록·준비물 탭·지갑으로 이동하므로
/// 그 자리 화면도 같이 둔다.
Future<({FakeTripApi api, SharedPreferences prefs, _FakeTripDeleter deleter})> pumpResultPage(
  WidgetTester tester, {
  Trip? trip,
  int? getTripStatusCode,
  Map<String, Object> stored = const {},
  bool deleteFails = false,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final api = FakeTripApi(tripToReturn: trip, getTripStatusCode: getTripStatusCode);
  final deleter = _FakeTripDeleter(fails: deleteFails);
  final id = (trip ?? sampleTrip()).id;

  final router = GoRouter(
    initialLocation: '/visa/trip/$id',
    routes: [
      GoRoute(path: '/visa', builder: (_, _) => const Scaffold(body: Text('여행 목록'))),
      GoRoute(
        path: '/visa/trip/:id',
        builder: (_, state) =>
            Scaffold(body: VisaResultPage(tripId: int.parse(state.pathParameters['id']!))),
      ),
      GoRoute(path: '/checklist', builder: (_, _) => const Scaffold(body: Text('준비물 탭'))),
      GoRoute(
        path: '/checklist/wallet',
        builder: (_, state) => Scaffold(
            body: Text('wallet ${state.uri.queryParameters['trip']} ${state.uri.queryParameters['iso']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tripApiProvider.overrideWithValue(api),
        tripDeleterProvider.overrideWithValue(deleter),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (api: api, prefs: prefs, deleter: deleter);
}

TripTask task({
  required int id,
  required String title,
  required DateTime dueDate,
  bool done = false,
}) {
  return TripTask(id: id, title: title, dueDate: dueDate, done: done);
}

void main() {
  testWidgets('없는 여행이면 안내하고 선택된 여행이었다면 선택을 지운다', (tester) async {
    final r = await pumpResultPage(tester, getTripStatusCode: 404, stored: {'selected_trip_id': 7});

    expect(find.textContaining('여행을 찾을 수 없습니다'), findsOneWidget);
    expect(r.prefs.getInt('selected_trip_id'), isNull);

    await tester.tap(find.text('목록으로'));
    await tester.pumpAndSettle();

    expect(find.text('여행 목록'), findsOneWidget);
  });

  testWidgets('[준비물 체크리스트]는 이 여행을 선택하고 준비물 탭으로 간다', (tester) async {
    final r = await pumpResultPage(tester);

    await tester.ensureVisible(find.byKey(const Key('openChecklistButton')));
    await tester.tap(find.byKey(const Key('openChecklistButton')));
    await tester.pumpAndSettle();

    expect(find.text('준비물 탭'), findsOneWidget);
    expect(r.prefs.getInt('selected_trip_id'), 7);
  });

  testWidgets('[지갑]은 이 여행의 지갑으로 간다', (tester) async {
    await pumpResultPage(tester);

    await tester.ensureVisible(find.byKey(const Key('openWalletButton')));
    await tester.tap(find.byKey(const Key('openWalletButton')));
    await tester.pumpAndSettle();

    expect(find.text('wallet 7 VN'), findsOneWidget);
  });

  testWidgets('메뉴의 여행 삭제는 확인 후 지우고 목록으로 간다', (tester) async {
    final r = await pumpResultPage(tester);

    await tester.tap(find.byKey(const Key('tripMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteTripMenuItem')));
    await tester.pumpAndSettle();
    expect(find.text('여행을 삭제할까요?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmDeleteTrip')));
    await tester.pumpAndSettle();

    expect(r.deleter.calls, [7]);
    expect(find.text('여행 목록'), findsOneWidget);
  });

  testWidgets('삭제가 실패하면 화면에 남아 안내한다', (tester) async {
    await pumpResultPage(tester, deleteFails: true);

    await tester.tap(find.byKey(const Key('tripMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteTripMenuItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteTrip')));
    await tester.pumpAndSettle();

    expect(find.text('여행을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(find.text('여행 목록'), findsNothing);
  });
```
(이어서 기존 `testWidgets('국가 이름과 판정 결과를 서버 데이터로 보여준다', ...` 부터가 그대로 이어진다. 기존 테스트 중 `final api = await pumpResultPage(...)` 형태로 반환값을 쓰는 두 곳(`'일정 항목을 누르면...'`, `'판정 기준이 바뀌었으면...'`)은 `final api = (await pumpResultPage(tester, trip: trip)).api;`로 고친다.)

`app/test/visa/visa_page_test.dart`:
- import에서 `import 'package:app/features/visa/data/trip_providers.dart';` 삭제
- `_pumpVisaPage`의 라우터를 다음으로 교체:
```dart
  final router = GoRouter(
    initialLocation: AppRoutes.visaNew,
    routes: [
      GoRoute(
        path: AppRoutes.visaNew,
        builder: (_, _) => const Scaffold(body: VisaPage()),
      ),
      GoRoute(
        path: AppRoutes.tripDetail,
        builder: (_, state) => Scaffold(body: Text('결과 ${state.pathParameters['id']}')),
      ),
    ],
  );
```
- `'모두 입력하고 제출하면 여행을 만들고 결과 화면으로 이동한다'` 테스트:
  - `final container = await _pumpVisaPage(tester, api: api);` → `await _pumpVisaPage(tester, api: api);`
  - `expect(container.read(activeTripIdProvider), 42);` 와 `expect(find.text('결과 화면'), findsOneWidget);` 두 줄 → `expect(find.text('결과 42'), findsOneWidget);`
  - 테스트 이름 → `'모두 입력하고 제출하면 여행을 만들고 그 여행의 상세로 이동한다'`
- `'서버가 거절하면 오류 문구를 보여주고 화면에 남는다'` 테스트:
  - `final container = await _pumpVisaPage(tester, api: api);` → `await _pumpVisaPage(tester, api: api);`
  - `expect(find.text('결과 화면'), findsNothing);` → `expect(find.textContaining('결과 '), findsNothing);`
  - `expect(container.read(activeTripIdProvider), isNull);` 삭제
- `_pumpVisaPage`의 반환 타입·`return ProviderScope.containerOf(...)`는 다른 테스트가 쓰지 않으면 `Future<void>`로 바꾸고 return 줄을 지운다(`dart analyze`가 미사용을 알려주면 정리).

`app/test/router_test.dart`:
- import 추가:
```dart
import 'package:app/features/visa/data/trip_list_providers.dart';
```
- `pumpApp`의 `ProviderScope(`를 다음으로:
```dart
    ProviderScope(
      // 첫 탭(여행 목록)이 서버를 부르지 않게 빈 목록으로 고정한다.
      overrides: [
        tripListProvider.overrideWith((ref) async => const TripListState(trips: [])),
      ],
```
- `'로그인했으면 첫 탭(비자)이 보인다'` → 이름 `'로그인했으면 첫 탭(여행)이 보인다'`, 주석·기대값 `find.text('비자')` → `find.text('여행')`

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/visa/ test/router_test.dart`
Expected: FAIL — `trip_list_page.dart`/`trip_deletion.dart` 없음, `VisaResultPage(tripId:)` 없음

- [ ] **Step 3: 구현 — 삭제 서비스**

`app/lib/features/visa/data/trip_deletion.dart` 생성:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../checklist/data/checklist_providers.dart';
import '../../wallet/data/wallet_database.dart';
import 'trip_api.dart';
import 'trip_list_providers.dart';

/// 여행 삭제(여행계획 중심 설계 §4.3). 서버 삭제가 성공한 뒤에만 기기 쪽 기록을 정리한다 —
/// 서버 삭제가 실패했는데 가계부부터 지우면 여행은 남고 기록만 사라진다.
class TripDeleter {
  TripDeleter(this.ref);

  final Ref ref;

  Future<void> delete(int tripId) async {
    await ref.read(tripApiProvider).deleteTrip(tripId);
    await ref.read(walletDatabaseProvider).clearWallet(tripId);
    await ref.read(powerBankCheckStoreProvider).remove(tripId);
    if (ref.read(selectedTripIdProvider) == tripId) {
      await ref.read(selectedTripIdProvider.notifier).clear();
    }
    ref.invalidate(tripListProvider);
  }
}

final tripDeleterProvider = Provider<TripDeleter>((ref) => TripDeleter(ref));
```

- [ ] **Step 4: 구현 — 여행 목록 화면**

`app/lib/features/visa/trip_list_page.dart` 생성:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import 'data/trip_list_providers.dart';
import 'models/trip_summary.dart';
import 'visa_result_display.dart';

/// 여행 탭의 첫 화면 — 내 여행 목록(여행계획 중심 설계 §3.1).
/// 다가오는 여행과 지난 여행을 나눠 보여주고, 카드를 누르면 여행 상세로 간다.
class TripListPage extends ConsumerWidget {
  const TripListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(tripListProvider);
    void openNew() => context.push(AppRoutes.visaNew);

    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('여행 계획', style: AppTextStyles.screenTitle),
              GestureDetector(
                key: const Key('createTripButton'),
                onTap: openNew,
                child: Text(
                  '+ 새 여행계획',
                  style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Message(
              text: '여행 목록을 불러오지 못했습니다.',
              actionLabel: '다시 시도',
              onAction: () => ref.invalidate(tripListProvider),
            ),
            data: (state) => RefreshIndicator(
              onRefresh: () async {
                try {
                  await ref.refresh(tripListProvider.future);
                } catch (_) {
                  // 캐시도 없이 실패하면 화면이 오류 상태로 바뀐다 — 여기서 따로 알릴 것은 없다.
                }
              },
              child: state.trips.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        _Message(
                          text: '첫 여행계획을 만들어 보세요',
                          actionLabel: '새 여행계획 만들기',
                          actionKey: const Key('emptyCreateTripButton'),
                          onAction: openNew,
                        ),
                      ],
                    )
                  : _TripListView(state: state),
            ),
          ),
        ),
      ],
    );
  }
}

class _TripListView extends StatelessWidget {
  const _TripListView({required this.state});

  final TripListState state;

  @override
  Widget build(BuildContext context) {
    final split = splitTrips(state.trips, DateTime.now());
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        if (state.offline) ...[
          Text('오프라인 · 마지막으로 불러온 목록', style: AppTextStyles.caption),
          const SizedBox(height: 12),
        ],
        if (split.upcoming.isNotEmpty) ...[
          const SectionLabel('다가오는 여행'),
          const SizedBox(height: 8),
          for (final t in split.upcoming) _TripCard(trip: t),
        ],
        if (split.upcoming.isNotEmpty && split.past.isNotEmpty) const SizedBox(height: 14),
        if (split.past.isNotEmpty) ...[
          const SectionLabel('지난 여행'),
          const SizedBox(height: 8),
          for (final t in split.past) _TripCard(trip: t),
        ],
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final TripSummary trip;

  Color _toneColor(BadgeTone tone) => switch (tone) {
        BadgeTone.info => AppColors.accent,
        BadgeTone.warn => AppColors.warn,
        BadgeTone.neutral => AppColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final chip = verdictChipOf(trip.verdict);
    final color = _toneColor(chip.tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        key: Key('tripCard_${trip.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(AppRoutes.tripOf(trip.id)),
        child: WireframeCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.countryNameKo, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 2),
                    Text(trip.dateRangeLabel, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(980),
                ),
                child: Text(chip.label, style: AppTextStyles.caption.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 20),
            TextButton(key: actionKey, onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 구현 — 라우터**

`app/lib/router.dart`:
- import 추가: `import 'features/visa/trip_list_page.dart';`
- `static const tabLabels = ['비자', ...` → `static const tabLabels = ['여행', '준비물', '발걸음', '그룹', '번역', '주변'];`
- `static const visaResult = '/visa/result';` 줄을 다음으로 교체:
```dart
  /// 여행 상세(판정·준비 일정). `tripOf(3)` → `/visa/trip/3`.
  static const tripDetail = '/visa/trip/:id';

  static String tripOf(int id) => '/visa/trip/$id';
```
- 라우트:
  - `GoRoute(path: AppRoutes.visa, builder: (_, _) => const VisaPage()),` → `GoRoute(path: AppRoutes.visa, builder: (_, _) => const TripListPage()),`
  - `GoRoute(path: AppRoutes.visaResult, builder: (_, _) => const VisaResultPage()),` →
```dart
          GoRoute(
            path: AppRoutes.tripDetail,
            builder: (_, state) =>
                VisaResultPage(tripId: int.parse(state.pathParameters['id']!)),
          ),
```

- [ ] **Step 6: 구현 — 새 여행 폼**

`app/lib/features/visa/visa_page.dart`:
- import에서 `import 'data/trip_providers.dart';` → `import 'data/trip_list_providers.dart';`
- 클래스 doc의 마지막 두 줄을 교체:
```dart
/// 새 여행계획 입력 폼(`/visa/new`, 여행 목록의 [+ 새 여행계획]에서 들어온다).
/// 와이어프레임: "해외여행 발걸음 - 와이어프레임" Plan B, 여행 계획 화면.
///
/// 제출하면 `POST /api/trips`로 비자 판정을 받고, 목록을 새로 고친 뒤 이 폼을 만들어진
/// 여행의 상세 화면으로 바꾼다 — 뒤로 가기는 폼이 아니라 목록으로 돌아간다.
```
- `_submit()`의
```dart
      await ref.read(activeTripIdProvider.notifier).set(trip.id);
      if (mounted) context.push(AppRoutes.visaResult);
```
→
```dart
      ref.invalidate(tripListProvider);
      if (mounted) context.pushReplacement(AppRoutes.tripOf(trip.id));
```
- `build()`의 헤더 Container의 `child: Text('여행 계획', style: AppTextStyles.screenTitle),` →
```dart
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(AppRoutes.visa),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Text('새 여행계획', style: AppTextStyles.screenTitle),
            ],
          ),
```

- [ ] **Step 7: 구현 — 여행 상세**

`app/lib/features/visa/visa_result_page.dart`:

1. 파일 처음부터 `class _Header`의 끝까지(`class _CenteredNotice` 바로 앞까지)를 다음으로 교체:
```dart
import 'package:app/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/trip_api.dart';
import 'data/trip_deletion.dart';
import 'data/trip_list_providers.dart';
import 'models/trip.dart';
import 'visa_page.dart' show tripErrorMessage;
import 'visa_result_display.dart';

final _shortDate = DateFormat('M/d');

bool _isNotFound(Object error) =>
    error is DioException && error.response?.statusCode == 404;

/// 여행 상세(`/visa/trip/:id`) — 판정·근거·준비 일정과 [준비물 체크리스트]·[지갑]·[여행 삭제].
///
/// 레이아웃은 와이어프레임("해외여행 발걸음 - 와이어프레임" Plan B)을 따르고,
/// 내용은 전부 [tripProvider]가 가져온 서버 판정 결과에서 나온다.
class VisaResultPage extends ConsumerWidget {
  const VisaResultPage({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 없는 여행(삭제됐거나 다른 계정)이 선택된 여행이었다면 선택을 지운다 — 준비물 탭이 다음에
    // 기본 여행 규칙으로 다시 고른다.
    ref.listen(tripProvider(tripId), (_, next) {
      final error = next.error;
      if (error != null && _isNotFound(error) && ref.read(selectedTripIdProvider) == tripId) {
        ref.read(selectedTripIdProvider.notifier).clear();
      }
    });
    final tripAsync = ref.watch(tripProvider(tripId));
    final countryName = tripAsync.asData?.value.countryNameKo;

    return Column(
      children: [
        _Header(
          title: countryName == null ? '판정 결과' : '$countryName 판정 결과',
          onDelete: tripAsync.hasValue ? () => _confirmDelete(context, ref) : null,
        ),
        Expanded(
          child: tripAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _isNotFound(e)
                ? _CenteredNotice(
                    message: '여행을 찾을 수 없습니다.\n삭제됐거나 다른 계정의 여행입니다.',
                    actionLabel: '목록으로',
                    onAction: () => context.go(AppRoutes.visa),
                  )
                : _CenteredNotice(
                    message: tripErrorMessage(e),
                    actionLabel: '다시 시도',
                    onAction: () => ref.invalidate(tripProvider(tripId)),
                  ),
            // 다시 판정하면 아래 화면의 로컬 상태(일정 완료 표시)를 새로 시작해야 하므로 id를 key로 준다.
            data: (trip) => _ResultBody(key: ValueKey(trip.id), trip: trip),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('여행을 삭제할까요?'),
        content: const Text('준비 일정·체크리스트와 이 여행의 지갑 기록이 모두 지워집니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const Key('confirmDeleteTrip'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tripDeleterProvider).delete(tripId);
      if (context.mounted) context.go(AppRoutes.visa);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('여행을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onDelete});

  final String title;

  /// 있으면 오른쪽에 메뉴(여행 삭제)를 보여준다. 여행을 불러오기 전에는 null.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.visa),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.screenTitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onDelete != null)
            PopupMenuButton<String>(
              key: const Key('tripMenu'),
              icon: const Icon(Icons.more_vert, color: AppColors.textBody),
              onSelected: (_) => onDelete!(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  key: Key('deleteTripMenuItem'),
                  value: 'delete',
                  child: Text('여행 삭제'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
```

2. `_ResultBodyState._refreshJudgement()`의 `if (mounted) setState(() => _trip = refreshed);` 다음 줄에 추가(목록의 판정 배지도 바뀔 수 있다):
```dart
      ref.invalidate(tripListProvider);
```

3. `_ResultBodyState.build()` 끝의
```dart
          PillOutlineButton(
            label: '준비물 체크리스트 보기',
            onPressed: () => context.push(AppRoutes.checklist),
          ),
```
→
```dart
          Row(
            children: [
              Expanded(
                child: PillOutlineButton(
                  key: const Key('openChecklistButton'),
                  label: '준비물 체크리스트',
                  onPressed: _openChecklist,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillOutlineButton(
                  key: const Key('openWalletButton'),
                  label: '지갑',
                  onPressed: () =>
                      context.push(AppRoutes.walletOf(_trip.id, _trip.countryIso2)),
                ),
              ),
            ],
          ),
```
그리고 `_refreshJudgement()` 메서드 아래에 추가:
```dart

  /// 이 여행을 준비물 탭의 선택된 여행으로 정하고 탭을 옮긴다.
  Future<void> _openChecklist() async {
    await ref.read(selectedTripIdProvider.notifier).set(_trip.id);
    if (mounted) context.go(AppRoutes.checklist);
  }
```

4. `trip_providers.dart` 삭제:
```bash
git rm app/lib/features/visa/data/trip_providers.dart app/test/visa/trip_providers_test.dart
```
Run: `grep -rn "trip_providers.dart\|activeTrip\|visaResult" lib test` → 결과가 없어야 한다.

- [ ] **Step 8: 전체 테스트 통과 확인**

Run: `flutter test && dart analyze`
Expected: 전체 PASS, `No issues found!`

- [ ] **Step 9: 커밋**

```bash
git add -A app/lib app/test
git commit -m "feat(app): 여행 탭을 내 여행 목록·새 여행·여행 상세로 재구성"
```

---

### Task 7: 마무리 — 실기기 확인·리뷰·PR

- [ ] **Step 1:** 서버 실행(`server/`에서 `./gradlew bootRun`, 백그라운드) → `adb reverse tcp:8080 tcp:8080` → `app/`에서 `flutter run --dart-define=API_BASE_URL=http://localhost:8080`
- [ ] **Step 2: 사용자 실기기 확인 목록** (사용자에게 전달)
  1. 여행 탭 첫 화면이 내 여행 목록이고, 앱을 껐다 켜도 목록이 남는다
  2. [+ 새 여행계획] → 판정 → 그 여행 상세로 가고, 뒤로 가면 목록
  3. 상세 [준비물 체크리스트] → 준비물 탭이 그 나라로 열린다(베트남 고정 아님)
  4. 준비물 체크 → 다른 탭 갔다 와도/앱 재시작해도 유지, [여행 바꾸기]로 다른 여행 선택
  5. 상세 [지갑] / 준비물 지갑 카드 → 그 여행 가계부(일본을 두 번 만들면 따로)
  6. 상세 메뉴 [여행 삭제] → 목록에서 사라지고 가계부도 지워짐
  7. 비행기 모드: 여행 목록·준비물 상단에 오프라인 안내, 지갑은 열림
- [ ] **Step 3:** `codex review --base master` → 지적 사항을 실제 파일로 검증 후 수정
- [ ] **Step 4:** 커밋 트레일러 확인 `git log master..HEAD --format='%B' | grep -i "co-authored\|claude"` → 결과 없음, push, PR 생성(사용자 승인 후 병합)
