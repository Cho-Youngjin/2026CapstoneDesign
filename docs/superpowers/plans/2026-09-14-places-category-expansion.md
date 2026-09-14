# Places 카테고리 확장 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `GET /api/places/nearby`가 지원하는 `PlaceCategory`를 4개(TOURIST/RESTAURANT/PHARMACY/ATM)에서 10개로 늘린다.

**Architecture:** `PlaceCategory` enum에 상수 6개를 추가하는 것만으로 끝난다 — 컨트롤러(`PlacesController`)·DTO(`PlaceResponse`)·클라이언트(`GooglePlacesClient`)는 전부 이 enum을 매개로 동작하도록 이미 설계돼 있어(Task 8, Plan A), 이 파일 하나 외에는 프로덕션 코드를 건드릴 필요가 없다.

**Tech Stack:** Spring Boot 3.5.3, Java 21, MockRestServiceServer(단위 테스트), MockMvc(`@WebMvcTest`)

## Global Constraints

- 새 카테고리의 Google Places `type` 값은 정확히 이 표를 따른다(임의 변경 금지): `LODGING`→`lodging`, `CONVENIENCE_STORE`→`convenience_store`, `SUPERMARKET`→`supermarket`, `HOSPITAL`→`hospital`, `MUSEUM`→`museum`, `AMUSEMENT_PARK`→`amusement_park`.
- 기존 4개 카테고리(`TOURIST`, `RESTAURANT`, `PHARMACY`, `ATM`)의 순서와 값은 그대로 유지한다 — 앱(Plan F)이 이미 이 문자열들을 알고 있을 수 있다.
- `docs/api-spec.md`(API 명세서)의 "부록: 국가 코드/enum 참고" 섹션도 이 Task 안에서 같이 갱신한다 — 문서와 코드가 어긋나면 안 된다.

---

### Task 1: `PlaceCategory` 확장 + 테스트

**Files:**
- Modify: `server/src/main/java/com/travelfootsteps/places/PlaceCategory.java`
- Modify: `server/src/test/java/com/travelfootsteps/places/GooglePlacesClientTest.java`
- Modify: `server/src/test/java/com/travelfootsteps/places/PlacesControllerTest.java`
- Modify: `docs/api-spec.md`

**Interfaces:**
- Consumes: 없음(기존 `PlacesClient`/`GooglePlacesClient`/`PlacesController`를 그대로 사용)
- Produces: `PlaceCategory` enum에 6개 상수 추가 — 이후 어떤 Task도 이 이름들(`LODGING`, `CONVENIENCE_STORE`, `SUPERMARKET`, `HOSPITAL`, `MUSEUM`, `AMUSEMENT_PARK`)을 그대로 참조한다.

- [ ] **Step 1: 실패하는 테스트 작성 — `GooglePlacesClientTest`에 신규 카테고리 왕복 검증 추가**

`server/src/test/java/com/travelfootsteps/places/GooglePlacesClientTest.java`의 기존 두 테스트 아래에 추가:

```java
    @Test
    void LODGING_카테고리는_구글_type_lodging으로_요청한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(),
                        requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(requestTo(containsString("type=lodging")))
                .andRespond(withSuccess("""
                        {"results":[{"place_id":"h1","name":"테스트 호텔","vicinity":"서울",
                        "geometry":{"location":{"lat":37.5,"lng":127.0}}}]}
                        """, MediaType.APPLICATION_JSON));

        List<PlaceResult> results = client.nearby(37.5, 127.0, 500, PlaceCategory.LODGING);

        assertThat(results).hasSize(1);
        assertThat(results.get(0).category()).isEqualTo(PlaceCategory.LODGING);
        server.verify();
    }
```

**Step 1의 나머지 5개 카테고리도 같은 패턴으로 추가한다** — 각 카테고리마다 `requestTo(containsString("type=<구글타입>"))`로 매핑이 맞는지 확인하는 테스트를 만든다. 예시(나머지도 동일한 구조로 작성):

```java
    @Test
    void CONVENIENCE_STORE_카테고리는_구글_type_convenience_store로_요청한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(),
                        requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(requestTo(containsString("type=convenience_store")))
                .andRespond(withSuccess("""
                        {"results":[]}
                        """, MediaType.APPLICATION_JSON));

        client.nearby(37.5, 127.0, 500, PlaceCategory.CONVENIENCE_STORE);

        server.verify();
    }

    @Test
    void SUPERMARKET_카테고리는_구글_type_supermarket로_요청한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(),
                        requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(requestTo(containsString("type=supermarket")))
                .andRespond(withSuccess("""
                        {"results":[]}
                        """, MediaType.APPLICATION_JSON));

        client.nearby(37.5, 127.0, 500, PlaceCategory.SUPERMARKET);

        server.verify();
    }

    @Test
    void HOSPITAL_카테고리는_구글_type_hospital로_요청한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(),
                        requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(requestTo(containsString("type=hospital")))
                .andRespond(withSuccess("""
                        {"results":[]}
                        """, MediaType.APPLICATION_JSON));

        client.nearby(37.5, 127.0, 500, PlaceCategory.HOSPITAL);

        server.verify();
    }

    @Test
    void MUSEUM_카테고리는_구글_type_museum으로_요청한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(),
                        requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(requestTo(containsString("type=museum")))
                .andRespond(withSuccess("""
                        {"results":[]}
                        """, MediaType.APPLICATION_JSON));

        client.nearby(37.5, 127.0, 500, PlaceCategory.MUSEUM);

        server.verify();
    }

    @Test
    void AMUSEMENT_PARK_카테고리는_구글_type_amusement_park로_요청한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(),
                        requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(requestTo(containsString("type=amusement_park")))
                .andRespond(withSuccess("""
                        {"results":[]}
                        """, MediaType.APPLICATION_JSON));

        client.nearby(37.5, 127.0, 500, PlaceCategory.AMUSEMENT_PARK);

        server.verify();
    }
```

- [ ] **Step 2: 실패하는 테스트 작성 — `PlacesControllerTest`에 신규 카테고리 엔드투엔드 케이스 추가**

`server/src/test/java/com/travelfootsteps/places/PlacesControllerTest.java`의 `TestBeans.placesClient()`에 mock 응답 하나를 추가:

```java
        @Bean
        PlacesClient placesClient() {
            PlacesClient mock = mock(PlacesClient.class);
            when(mock.nearby(eq(37.5), eq(127.0), eq(500), eq(PlaceCategory.RESTAURANT)))
                    .thenReturn(List.of(new PlaceResult("p1", "테스트 식당", PlaceCategory.RESTAURANT,
                            "서울", 37.5, 127.0)));
            when(mock.nearby(eq(37.5), eq(127.0), eq(500), eq(PlaceCategory.MUSEUM)))
                    .thenReturn(List.of(new PlaceResult("m1", "테스트 미술관", PlaceCategory.MUSEUM,
                            "서울", 37.5, 127.0)));
            return mock;
        }
```

그리고 기존 `카테고리로_주변정보를_조회한다()` 테스트 아래에 추가:

```java
    @Test
    void 신규_카테고리_MUSEUM으로도_조회된다() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .header("Authorization", "Bearer valid-token")
                        .param("lat", "37.5").param("lng", "127.0")
                        .param("radius", "500").param("category", "MUSEUM"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("테스트 미술관"))
                .andExpect(jsonPath("$[0].category").value("MUSEUM"));
    }
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*GooglePlacesClientTest*' --tests '*PlacesControllerTest*'
```

기대: 컴파일 실패 — `PlaceCategory.LODGING`, `PlaceCategory.CONVENIENCE_STORE`, `PlaceCategory.SUPERMARKET`, `PlaceCategory.HOSPITAL`, `PlaceCategory.MUSEUM`, `PlaceCategory.AMUSEMENT_PARK` 심볼을 찾을 수 없음.

- [ ] **Step 4: `PlaceCategory` enum 확장**

`server/src/main/java/com/travelfootsteps/places/PlaceCategory.java` 전체를 아래로 교체:

```java
package com.travelfootsteps.places;

// 앱(Plan F)이 쓰는 카테고리 값과 Google Places API가 쓰는 타입 문자열은 이름이 다르다
// (예: 우리 앱은 TOURIST, Google은 "tourist_attraction"). 이 enum이 그 매핑을 한 곳에
// 모아둔다 — 나중에 Google이 place type 이름을 바꾸거나 다른 지도 제공사로 교체하더라도,
// 이 매핑 하나만 고치면 되고 컨트롤러나 앱 쪽 계약(TOURIST 등)은 그대로 유지된다.
public enum PlaceCategory {
    TOURIST("tourist_attraction"),
    RESTAURANT("restaurant"),
    PHARMACY("pharmacy"),
    ATM("atm"),
    LODGING("lodging"),
    CONVENIENCE_STORE("convenience_store"),
    SUPERMARKET("supermarket"),
    HOSPITAL("hospital"),
    MUSEUM("museum"),
    AMUSEMENT_PARK("amusement_park");

    private final String googlePlaceType;

    PlaceCategory(String googlePlaceType) {
        this.googlePlaceType = googlePlaceType;
    }

    public String googlePlaceType() {
        return googlePlaceType;
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*GooglePlacesClientTest*' --tests '*PlacesControllerTest*'
```

기대: 전부 PASS (기존 3개 + 신규 7개 = `GooglePlacesClientTest` 8개, `PlacesControllerTest` 4개).

- [ ] **Step 6: `docs/api-spec.md` 갱신**

"부록: 국가 코드/enum 참고" 섹션의 `PlaceCategory` 목록을:

```
- `PlaceCategory`: `TOURIST`, `RESTAURANT`, `PHARMACY`, `ATM`
```

다음으로 교체:

```
- `PlaceCategory`: `TOURIST`, `RESTAURANT`, `PHARMACY`, `ATM`, `LODGING`, `CONVENIENCE_STORE`, `SUPERMARKET`, `HOSPITAL`, `MUSEUM`, `AMUSEMENT_PARK`
```

"6. 주변 정보 (Places 프록시)" 섹션의 `category` 파라미터 설명도 같이 갱신:

```
| `category` | ✓ | - | `TOURIST` \| `RESTAURANT` \| `PHARMACY` \| `ATM` \| `LODGING` \| `CONVENIENCE_STORE` \| `SUPERMARKET` \| `HOSPITAL` \| `MUSEUM` \| `AMUSEMENT_PARK` |
```

- [ ] **Step 7: 전체 회귀 테스트**

```bash
cd server && ./gradlew test
```

기대: 기존 테스트 전부 PASS, 신규 테스트 전부 PASS (Docker/Testcontainers 필요한 테스트는 로컬에서 실행 불가 — 이 프로젝트의 알려진 환경 제약, 코드와 무관).

- [ ] **Step 8: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/places/PlaceCategory.java \
  server/src/test/java/com/travelfootsteps/places/GooglePlacesClientTest.java \
  server/src/test/java/com/travelfootsteps/places/PlacesControllerTest.java \
  docs/api-spec.md
git commit -m "feat(server): Places 카테고리 4개 -> 10개 확장 (숙소/편의점/마트/병원/미술관/놀이공원)"
```

---

## Self-Review

**스펙 커버리지**: `docs/superpowers/specs/2026-09-14-places-expansion-and-deployment-design.md`의 "1. Places 카테고리 확장" 섹션 — 카테고리 6개 추가(표 그대로 반영), 코드 변경 범위(enum 하나), 테스트 요구사항(신규 카테고리 최소 1개 왕복 검증 + 컨트롤러 엔드투엔드) 전부 Task 1에서 커버됨. "스코프 밖"으로 명시된 Flutter UI는 이 계획에 포함하지 않음(의도된 범위).
