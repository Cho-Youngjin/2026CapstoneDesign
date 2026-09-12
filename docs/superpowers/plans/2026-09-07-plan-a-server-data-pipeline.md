# Plan A — 서버: 공공데이터 파이프라인 + 비자 규칙 엔진 + 프록시 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 외교부 공공데이터(입국허가요건·여행경보·재외공관)를 일 1회 배치로 수집·정규화하고, 비자 규칙 엔진으로 여행 계획을 판정해 역산 일정을 생성하며, 번역·Places·환율을 서버 프록시/캐시로 제공한다. 완료 시 `POST /api/trips`에 목적지·일정·여권만료일을 보내면 비자 판정과 역산 일정이 돌아오고, 앱의 번역·주변정보·환율 화면이 실제 데이터로 채워진다.

**Architecture:** Spring Boot 배치(`@Scheduled`, 일 1회)가 공공데이터포털의 세 데이터셋을 국가별로 호출해 PostgreSQL에 적재한다. 입국허가요건의 `gnrl_pspt_visa_cn` 자연어 필드는 정규식 기반 `VisaConditionParser`가 `{visaRequired, visaFreeDays, passportValidityMonths}`로 정규화하며, 파싱에 실패하면 `visaFreeDays = null`로 남겨 Tier B degrade("영사관 확인 필요")를 유도한다. Tier A 20개국은 `verified = true`가 되면 배치가 판정 필드를 덮어쓰지 않고 원문 필드만 갱신한다. 비자 판정은 DB에 저장된 `visa_requirement`를 순수 도메인 서비스(`VisaJudgementService`)로 계산한다. **`POST /api/trips` 생성 시점에 한 번 계산해 `trip`에 스냅샷으로 고정하고, `GET /api/trips/{id}`는 그 스냅샷을 그대로 반환한다(재계산하지 않는다) — 원본 데이터가 나중에 바뀌어도 이미 만든 여행 일정과 예약된 알람이 조용히 어긋나지 않도록, 최신 규칙과 다르면 `judgementStale=true`만 표시하고 실제 갱신은 사용자가 명시적으로 `POST /api/trips/{id}/refresh`를 호출할 때만 일어난다** (2026-09-12 리뷰 반영 — 상세는 Task 6 참고). 번역·Places는 외부 API 키를 숨기는 얇은 프록시 컨트롤러이며, 번역은 인터페이스(`TranslationClient`) 뒤에 두어 나중에 LLM 티어로 교체 가능하게 한다. 환율은 한국수출입은행 API를 일 1회 캐시하는 가장 낮은 우선순위(T3) 기능이다.

**Tech Stack:** Spring Boot 3.x / Java 21 (Phase 0 기반) · Spring Data JPA + Flyway · `RestClient`(Spring Web, 별도 리액티브 의존성 불필요) · `spring-retry` + `spring-boot-starter-aop`(재시도) · `@Scheduled`(배치) · Firebase Admin SDK(Firestore로 FCM 토큰 조회, T3 환전 알림) · PostgreSQL 16

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §3, §4, §5, §6-①⑦, §7, §12

## Global Constraints

Phase 0의 제약을 상속한다(모노레포, `com.travelfootsteps` 패키지 루트, 서버 포트 8080, `feature/*` → `develop` PR 2인 승인, 매주 금요일 `develop` 머지, 비밀정보 미커밋, `TokenVerifier` 추상화로 컨트롤러 테스트는 실제 Firebase를 호출하지 않음). 이 계획에 특화된 제약은 아래와 같다.

- **이 계획은 서버(`server/`)만 수정한다.** 앱(`app/`) 코드는 건드리지 않는다. 앱은 이미 작성된 Plan B/E/F가 이 계획의 API를 소비한다.
- **마이그레이션은 `V2`부터 이어간다.** Phase 0 Task 4가 `V1__init.sql`(country 테이블)을 만들었다. 이 계획은 `V2__visa_requirement.sql`, `V3__travel_alert_embassy.sql`, `V4__trip.sql`, `V5__checklist_template.sql`, `V6__exchange_rate.sql`, `V7__footsteps.sql`(Task 11), `V8__trip_checklist.sql`(Task 7, 2026-09-12 리뷰 반영) 순서로 추가한다. 번호를 건너뛰거나 재사용하지 않는다.
- **응답 계약은 Plan B/E/F가 이미 가정한 JSON 모양을 그대로 따른다** (이 계획서 작성 시점에 세 계획서가 먼저 존재하며 서버 계약을 구체적으로 명시해 두었다). 필드명이 다르면 앱 쪽 3개 계획서를 전부 다시 고쳐야 하므로, 이 계획의 모든 DTO는 아래 표와 **정확히 일치**해야 한다.

  | 엔드포인트 | 응답/요청 필드 | 출처 |
  |---|---|---|
  | `POST /api/trips`, `GET /api/trips/{id}` | 요청 `{countryIso2, departDate, returnDate, passportExpiry}`(yyyy-MM-dd). 응답 `{id, countryIso2, countryNameKo, departDate, returnDate, passportExpiry, visaResult{verdict, stayDays, visaFreeDays, passportOk, passportValidityMonths, passportShortfallDays}, tasks[{id, title, dueDate, done}]}` | Plan B (`app/lib/features/visa/data/trip_api.dart`, `models/trip.dart`) |
  | `verdict` 문자열 값 | `VISA_FREE_OK` \| `VISA_FREE_EXCEEDED` \| `VISA_REQUIRED` \| `UNVERIFIED` | Plan B `VisaVerdict` enum의 `wireValue` |
  | `POST /api/trips/{id}/tasks/{taskId}/done` | 응답 `{id, title, dueDate, done: true}` | Plan B |
  | `GET /api/countries/{iso2}` | Phase 0 `Country` 엔티티 컬럼을 camelCase로 노출 | Plan B |
  | `GET /api/countries/{iso2}/checklist` | `[{id, category, title, description, priority}]` — `checked` 필드 없음 | Plan B |
  | `GET /api/countries/{iso2}/alerts` | `[{id, level, region, title, issuedAt}]` | Plan F |
  | `GET /api/countries/{iso2}/embassies` | `[{id, type, name, lat, lng, phone, emergencyPhone, address}]` | Plan F |
  | `GET /api/places/nearby?lat&lng&radius&category` | `category ∈ TOURIST\|RESTAURANT\|PHARMACY\|ATM`. 응답 `[{id, name, category, address, lat, lng}]` | Plan F |
  | `POST /api/translate` | 요청 `{text, targetLanguage, sourceLanguage?}`. 응답 `{translatedText, detectedSourceLanguage?}` | Plan E |
  | `GET /api/exchange-rates/{currencyCode}` | `{currencyCode, krwRate, baseDate}` | Plan B |

- **외부 API 호출 실패 시 재시도/degrade 정책 (신규 제약)**:
  - 배치(공공데이터 3종)는 국가 단위로 최대 3회, 1s/2s/4s 지수 백오프로 재시도한다(`spring-retry` `@Retryable`). 재시도가 모두 실패하면 **그 국가만 건너뛰고 다음 국가로 진행** — 기존 DB 행은 그대로 둔다(마지막 성공 데이터가 최신 데이터보다 낫다). 배치 전체가 한 국가의 실패로 중단되지 않는다.
  - 사용자 요청 경로(번역/Places/환율 조회)는 재시도 1회(즉시)만 하고, 그래도 실패하면 `502 Bad Gateway`로 앱에 전달한다. 사용자를 기다리게 하는 재시도 지수 백오프는 쓰지 않는다.
  - `visa_requirement.visa_free_days`가 `null`이면(파싱 실패 또는 아직 수집 전) 판정 엔진은 **항상 `UNVERIFIED`를 반환한다** — 이 규칙이 최우선이며 다른 조건보다 먼저 검사한다 (스펙 §6-①).
- **파서 테스트는 실제 공공데이터 샘플 문장을 최우선으로 쓴다.** 스펙 §4가 인용한 실제 문구 `"관광 목적 90일 무비자"`를 정규 테스트 케이스로 포함한다. 이 계획서 작성 시점에는 아직 실제 API 응답 전체를 확보하지 못했으므로(활용신청은 Phase 0 Task 2가 진행 중), 나머지 케이스는 외교부가 실제로 쓰는 것으로 알려진 관용 표현(개월 단위 표기, 협정에 의한 무비자, 여권 잔여유효기간 문구)을 근거로 작성한다. **Task 3 착수 시 실제 API 응답을 curl로 받아(Phase 0 Task 2 Step 2 참고) `docs/`에 원본 샘플 몇 건을 저장하고, 그 문장들을 파서 테스트에 추가해야 한다.** 이 스텝을 빠뜨리면 파서가 실제 데이터에서 검증되지 않은 채로 배치에 들어간다.
- **Tier A(verified=true) 데이터는 배치가 판정 필드를 덮어쓰지 않는다.** `raw_text`/`evidence_text`/`remark`/`source_fetched_at`만 갱신한다. `verified`를 `true`로 세팅하는 것은 이 계획의 범위 밖이다(R4가 수기 검증 후 DB를 직접 갱신하거나, 별도의 관리 스크립트로 처리 — 이 계획은 그 스크립트를 만들지 않는다. 아래 Self-Review에서 이 결정을 다시 짚는다).
- **일반여권(GENERAL)만 다룬다.** 관용여권/외교관여권(`ofclpspt_visa_*`, `dplmt_pspt_visa_*`)은 스펙 §6-①이 "일반여권" 기준으로만 판정 로직을 명시하므로 이번 배치·판정 엔진의 범위 밖으로 둔다. `passport_type` 컬럼은 향후 확장을 위해 남겨 두되 이 계획은 `GENERAL` 행만 만든다.
  > **적용 대상 재확인 (2026-09-12, 실제 CSV로 검증)**: 공공데이터의 실제 컬럼은 국가별로 "일반여권소지자/관용여권소지자/외교관여권소지자" 3종 × (입국가능여부, 입국가능기간)과 "무비자 입국 근거"뿐이며, 여행 목적(관광/상용 등)을 구분하는 컬럼은 존재하지 않는다. 따라서 "판정 대상이 불명확하다"는 지적은 **여권 종류는 일반여권 컬럼만 쓰면 되고(위 결정과 동일), 목적 구분 필드는 원본 데이터 자체에 없으므로 앱에서도 별도로 받거나 처리할 필요가 없다**로 해소된다. 이 데이터셋은 애초에 대한민국 외교부가 대한민국 국민(일반여권 소지자) 기준으로 발행하는 자료이므로 여권 발급국도 별도로 명시할 필요가 없다.
- **T3 우선순위 규칙**: Task 1~8은 T1/T2 기능을 지원하므로 반드시 구현한다. **Task 9(환율 캐시)는 T3다.** 일정이 밀리면 Task 9를 가장 먼저 자른다. Task 9 안에서도 "환전 알림(FCM)" 서브스텝이 캐시·조회 API보다 우선순위가 낮으므로, Task 9마저 시간이 부족하면 그 서브스텝만 생략할 수 있다(스펙 §10 "자르는 순서" 1번과 일치).

---

## File Structure

```
server/
├── build.gradle                                   Modify: spring-retry, aop 의존성 추가
├── src/main/java/com/travelfootsteps/
│   ├── TravelFootstepsApplication.java            Modify: @EnableScheduling, @EnableRetry
│   ├── auth/                                      (Phase 0, 변경 없음)
│   ├── externaldata/
│   │   ├── DataGoKrProperties.java                serviceKey 설정 바인딩 (Task 1)
│   │   ├── DataGoKrHttpClient.java                공통 GET + 재시도 (Task 1)
│   │   ├── DataGoKrEnvelope.java                  응답 봉투 DTO (Task 1)
│   │   └── ExternalApiException.java              재시도 소진 후 예외 (Task 1)
│   ├── visa/
│   │   ├── VisaConditionParser.java               자연어 파서 — 핵심 구현물 (Task 2)
│   │   ├── ParsedVisaCondition.java                파서 출력 레코드 (Task 2)
│   │   ├── VisaRequirement.java                    JPA 엔티티 (Task 3)
│   │   ├── VisaRequirementRepository.java          (Task 3)
│   │   ├── EntranceVisaApiItem.java                API 응답 매핑 레코드 (Task 3)
│   │   ├── EntranceVisaClient.java                 입국허가요건 API 클라이언트 (Task 3)
│   │   ├── VisaRequirementCollector.java           수집→파싱→upsert (Task 3)
│   │   ├── VisaJudgement.java                      판정 결과 레코드 (Task 5)
│   │   ├── VisaVerdict.java                        판정 enum (Task 5)
│   │   └── VisaJudgementService.java               규칙 엔진 (Task 5)
│   ├── alert/
│   │   ├── TravelAlert.java, TravelAlertRepository.java
│   │   ├── TravelAlertApiItem.java, TravelAlertClient.java, TravelAlertCollector.java
│   │   ├── TravelAlertResponse.java, TravelAlertController.java   (모두 Task 4)
│   ├── embassy/
│   │   ├── Embassy.java, EmbassyRepository.java
│   │   ├── EmbassyApiItem.java, EmbassyClient.java, EmbassyCollector.java
│   │   ├── EmbassyResponse.java, EmbassyController.java          (모두 Task 4)
│   ├── batch/
│   │   └── DailyDataCollectionScheduler.java       일 1회 오케스트레이션 (Task 4)
│   ├── trip/
│   │   ├── Trip.java, TripTask.java, TripRepository.java, TripTaskRepository.java (Task 6)
│   │   ├── ScheduleGenerator.java                  역산 일정 생성기 (Task 5)
│   │   ├── TripController.java                     POST/GET/done (Task 6)
│   │   ├── CreateTripRequest.java, TripResponse.java, VisaResultResponse.java, TripTaskResponse.java (Task 6)
│   │   └── TripNotFoundException.java              (Task 6)
│   ├── country/                                    (Phase 0 패키지, 이 계획이 확장)
│   │   ├── Country.java, CountryRepository.java    (Phase 0, 변경 없음)
│   │   ├── CountryController.java                  Modify: `/{iso2}` 추가 (Task 7)
│   │   ├── CountryDetailResponse.java               (Task 7)
│   │   ├── ChecklistTemplate.java, ChecklistTemplateRepository.java (Task 7)
│   │   └── ChecklistTemplateResponse.java           (Task 7)
│   ├── translate/
│   │   ├── TranslationClient.java                   인터페이스 (Task 8)
│   │   ├── GoogleTranslateClient.java                구현체 (Task 8)
│   │   ├── TranslationResult.java, TranslateRequest.java, TranslateResponse.java, TranslateController.java (Task 8)
│   ├── places/
│   │   ├── PlacesClient.java, GooglePlacesClient.java (Task 8)
│   │   ├── PlaceCategory.java, PlaceResult.java, PlaceResponse.java, PlacesController.java (Task 8)
│   └── exchangerate/
│       ├── ExchangeRate.java, ExchangeRateRepository.java (Task 9)
│       ├── KoreaEximClient.java, ExchangeRateBatchScheduler.java (Task 9)
│       ├── ExchangeRateResponse.java, ExchangeRateController.java (Task 9)
│       └── ExchangeAlertScheduler.java              FCM 환전 알림, 여유 없으면 생략 (Task 9)
├── src/main/resources/
│   ├── application.yml                             Modify: data-go-kr, google, korea-exim 설정 추가
│   └── db/migration/
│       ├── V2__visa_requirement.sql   (Task 3)
│       ├── V3__travel_alert_embassy.sql (Task 4)
│       ├── V4__trip.sql               (Task 6)
│       ├── V5__checklist_template.sql (Task 7)
│       └── V6__exchange_rate.sql      (Task 9)
└── src/test/java/com/travelfootsteps/
    ├── support/StubTokenVerifier.java              (Phase 0, 재사용)
    ├── support/StubDataGoKrHttpClient.java          (Task 1)
    ├── visa/VisaConditionParserTest.java             (Task 2)
    ├── visa/VisaRequirementCollectorTest.java        (Task 3)
    ├── visa/VisaJudgementServiceTest.java             (Task 5)
    ├── alert/TravelAlertControllerTest.java           (Task 4)
    ├── embassy/EmbassyControllerTest.java              (Task 4)
    ├── batch/DailyDataCollectionSchedulerTest.java      (Task 4)
    ├── trip/ScheduleGeneratorTest.java                 (Task 5)
    ├── trip/TripControllerTest.java                    (Task 6)
    ├── country/CountryControllerTest.java              Modify (Task 7)
    ├── country/ChecklistTemplateControllerTest.java     (Task 7 — CountryController에 통합)
    ├── translate/TranslateControllerTest.java           (Task 8)
    ├── places/PlacesControllerTest.java                 (Task 8)
    └── exchangerate/ExchangeRateControllerTest.java      (Task 9)
```

**분리 원칙**: `externaldata`는 "공공데이터포털에 어떻게 접속하는가"만 안다 — 무엇을 수집하는지는 모른다. `visa`/`alert`/`embassy`는 각자의 도메인 데이터만 다루며 서로를 참조하지 않는다(둘 다 `country_id`로만 연결). `batch`는 오케스트레이션만 하고 파싱·판정 로직을 갖지 않는다 — 이 경계가 없으면 스케줄러 클래스가 비대해져 단위 테스트가 스프링 컨텍스트 없이는 불가능해진다. `trip`은 `visa`의 `VisaJudgementService`를 소비하지만 반대 방향 의존은 없다.

---

### Task 1: 외교부 공공데이터 공통 클라이언트 인프라

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/externaldata/DataGoKrProperties.java`
- Create: `server/src/main/java/com/travelfootsteps/externaldata/DataGoKrEnvelope.java`
- Create: `server/src/main/java/com/travelfootsteps/externaldata/ExternalApiException.java`
- Create: `server/src/main/java/com/travelfootsteps/externaldata/DataGoKrHttpClient.java`
- Create: `server/src/test/java/com/travelfootsteps/support/StubDataGoKrHttpClient.java`
- Modify: `server/build.gradle`
- Modify: `server/src/main/resources/application.yml`
- Modify: `server/src/main/java/com/travelfootsteps/TravelFootstepsApplication.java`

**Interfaces:**
- Consumes: 없음 (Plan A의 첫 태스크)
- Produces:
  - `DataGoKrHttpClient.getItems(String path, Map<String, String> queryParams, Class<T> itemType)` → `List<T>` — 봉투를 벗기고 `resultCode != "00"`이면 `ExternalApiException`을 던진다. 최대 3회 재시도(1s/2s/4s) 후에도 실패하면 `ExternalApiException`을 던진다.
  - Task 3(`EntranceVisaClient`), Task 4(`TravelAlertClient`, `EmbassyClient`)가 이 클라이언트 하나를 공유한다.

- [ ] **Step 1: 의존성 추가**

`server/build.gradle`의 `dependencies` 블록에 추가한다.

```gradle
    implementation 'org.springframework.retry:spring-retry'
    implementation 'org.springframework.boot:spring-boot-starter-aop'
```

- [ ] **Step 2: 설정 클래스 작성**

`server/src/main/java/com/travelfootsteps/externaldata/DataGoKrProperties.java`:

```java
package com.travelfootsteps.externaldata;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "data-go-kr")
public record DataGoKrProperties(String serviceKey) {
}
```

`server/src/main/resources/application.yml`에 아래를 추가한다 (기존 내용 유지, 파일 끝에 추가).

```yaml
data-go-kr:
  service-key: ${DATA_GO_KR_SERVICE_KEY:}

google:
  server-api-key: ${GOOGLE_SERVER_API_KEY:}

korea-exim:
  api-key: ${KOREA_EXIM_API_KEY:}
```

`server/src/main/java/com/travelfootsteps/TravelFootstepsApplication.java`을 수정해 설정 바인딩과 재시도, 스케줄링을 켠다. `@SpringBootApplication` 클래스 선언 위에 아래 애너테이션을 추가하고 import를 더한다.

```java
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.retry.annotation.EnableRetry;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@EnableRetry
@ConfigurationPropertiesScan
```

- [ ] **Step 3: 예외와 응답 봉투 정의**

`server/src/main/java/com/travelfootsteps/externaldata/ExternalApiException.java`:

```java
package com.travelfootsteps.externaldata;

public class ExternalApiException extends RuntimeException {
    public ExternalApiException(String message) {
        super(message);
    }

    public ExternalApiException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

`server/src/main/java/com/travelfootsteps/externaldata/DataGoKrEnvelope.java` — 공공데이터포털의 공통 JSON 응답 구조(`response.header.resultCode`, `response.body.items.item[]`)를 그대로 반영한다.

```java
package com.travelfootsteps.externaldata;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.JsonNode;

@JsonIgnoreProperties(ignoreUnknown = true)
public record DataGoKrEnvelope(Response response) {

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Response(Header header, Body body) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Header(String resultCode, String resultMsg) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Body(Items items) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Items(JsonNode item) {
    }
}
```

`item`을 `JsonNode`로 받는 이유는 결과가 0건일 때 문자열(`""`)로, 1건일 때 객체로, 여러 건일 때 배열로 오는 공공데이터포털의 흔한 비일관성을 흡수하기 위해서다. 실제 타입 변환은 `DataGoKrHttpClient`가 담당한다.

- [ ] **Step 4: 테스트용 스텁 작성**

`server/src/test/java/com/travelfootsteps/support/StubDataGoKrHttpClient.java` — 배치·수집기 테스트가 실제 HTTP를 타지 않게 한다.

```java
package com.travelfootsteps.support;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import com.travelfootsteps.externaldata.ExternalApiException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class StubDataGoKrHttpClient extends DataGoKrHttpClient {

    private final Map<String, List<?>> responses = new HashMap<>();
    private final Map<String, ExternalApiException> failures = new HashMap<>();

    public StubDataGoKrHttpClient() {
        super(null, null);
    }

    public <T> void whenCalled(String path, String countryIso2, List<T> items) {
        responses.put(key(path, countryIso2), items);
    }

    public void whenCalledFail(String path, String countryIso2, ExternalApiException exception) {
        failures.put(key(path, countryIso2), exception);
    }

    @Override
    @SuppressWarnings("unchecked")
    public <T> List<T> getItems(String path, Map<String, String> queryParams, Class<T> itemType) {
        String countryIso2 = queryParams.getOrDefault("cond[country_iso_alp2::EQ]", "");
        String k = key(path, countryIso2);
        if (failures.containsKey(k)) {
            throw failures.get(k);
        }
        return (List<T>) responses.getOrDefault(k, List.of());
    }

    private String key(String path, String countryIso2) {
        return path + "|" + countryIso2;
    }
}
```

`super(null, null)`이 가능하려면 `DataGoKrHttpClient`의 필드가 실제로 쓰이지 않는 오버라이드된 메서드 안에서만 참조되어야 한다 — Step 6에서 `getItems`를 `protected`가 아니라 `public`이고 오버라이드 가능하게 설계하는 이유다.

- [ ] **Step 5: 실패하는 테스트로 재시도 동작 정의**

`server/src/test/java/com/travelfootsteps/externaldata/DataGoKrHttpClientTest.java`:

```java
package com.travelfootsteps.externaldata;

import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class DataGoKrHttpClientTest {

    record DummyItem(String countryNm) {
    }

    @Test
    void resultCode_00이면_item_목록을_반환한다() {
        String body = """
                {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE"},
                "body":{"items":{"item":[{"countryNm":"베트남"}]}}}}
                """;
        RestClient restClient = RestClient.builder()
                .requestInterceptor((request, requestBody, execution) ->
                        new org.springframework.mock.http.client.MockClientHttpResponse(
                                body.getBytes(), org.springframework.http.HttpStatus.OK))
                .build();
        DataGoKrHttpClient client = new DataGoKrHttpClient(restClient, new DataGoKrProperties("key"));

        List<DummyItem> items = client.getItems("/test", Map.of(), DummyItem.class);

        assertThat(items).hasSize(1);
        assertThat(items.get(0).countryNm()).isEqualTo("베트남");
    }

    @Test
    void resultCode가_00이_아니면_3회_재시도_후_예외를_던진다() {
        AtomicInteger attempts = new AtomicInteger();
        String errorBody = """
                {"response":{"header":{"resultCode":"99","resultMsg":"UNKNOWN ERROR"},"body":{"items":{"item":""}}}}
                """;
        RestClient restClient = RestClient.builder()
                .requestInterceptor((request, requestBody, execution) -> {
                    attempts.incrementAndGet();
                    return new org.springframework.mock.http.client.MockClientHttpResponse(
                            errorBody.getBytes(), org.springframework.http.HttpStatus.OK);
                })
                .build();
        DataGoKrHttpClient client = new DataGoKrHttpClient(restClient, new DataGoKrProperties("key"));

        assertThatThrownBy(() -> client.getItems("/test", Map.of(), DummyItem.class))
                .isInstanceOf(ExternalApiException.class);
        assertThat(attempts.get()).isEqualTo(3);
    }
}
```

> `@Retryable`은 프록시 기반이라 같은 클래스 내부 호출에는 적용되지 않는다. 이 테스트가 스프링 컨텍스트 없이 재시도를 검증하려면 `DataGoKrHttpClient`가 재시도 로직을 `RetryTemplate`으로 직접 구현해야 한다 — Step 6에서 `@Retryable` 대신 `RetryTemplate`을 쓰는 이유다.

- [ ] **Step 6: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*DataGoKrHttpClientTest*'
```

기대: 컴파일 실패 — `DataGoKrHttpClient` 심볼을 찾을 수 없음.

- [ ] **Step 7: 클라이언트 구현**

`server/src/main/java/com/travelfootsteps/externaldata/DataGoKrHttpClient.java`:

```java
package com.travelfootsteps.externaldata;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.retry.RetryCallback;
import org.springframework.retry.backoff.FixedBackOffPolicy;
import org.springframework.retry.policy.SimpleRetryPolicy;
import org.springframework.retry.support.RetryTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 공공데이터포털(data.go.kr) 외교부 오픈API 공통 클라이언트.
 * 국가 단위 호출 실패 시 1s/2s/4s 간격으로 최대 3회 재시도하고,
 * 그래도 실패하면 {@link ExternalApiException}을 던진다 — 호출부(수집기)가
 * 그 국가만 건너뛰고 배치를 계속 진행할 수 있게 한다.
 */
@Component
public class DataGoKrHttpClient {

    private final RestClient restClient;
    private final DataGoKrProperties properties;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public DataGoKrHttpClient(RestClient.Builder restClientBuilder, DataGoKrProperties properties) {
        this.restClient = restClientBuilder != null
                ? restClientBuilder.baseUrl("https://apis.data.go.kr").build()
                : null;
        this.properties = properties;
    }

    // 테스트에서 RestClient 인스턴스를 직접 주입하기 위한 생성자
    DataGoKrHttpClient(RestClient restClient, DataGoKrProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    public <T> List<T> getItems(String path, Map<String, String> queryParams, Class<T> itemType) {
        RetryTemplate retryTemplate = buildRetryTemplate();
        RetryCallback<List<T>, ExternalApiException> callback = context -> fetchOnce(path, queryParams, itemType);
        return retryTemplate.execute(callback);
    }

    private <T> List<T> fetchOnce(String path, Map<String, String> queryParams, Class<T> itemType) {
        Map<String, String> allParams = new LinkedHashMap<>(queryParams);
        allParams.putIfAbsent("serviceKey", properties.serviceKey());
        allParams.putIfAbsent("returnType", "JSON");

        String responseBody = restClient.get()
                .uri(uriBuilder -> {
                    var builder = uriBuilder.path(path);
                    allParams.forEach(builder::queryParam);
                    return builder.build();
                })
                .retrieve()
                .body(String.class);

        try {
            DataGoKrEnvelope envelope = objectMapper.readValue(responseBody, DataGoKrEnvelope.class);
            if (envelope.response() == null || envelope.response().header() == null
                    || !"00".equals(envelope.response().header().resultCode())) {
                String msg = envelope.response() != null && envelope.response().header() != null
                        ? envelope.response().header().resultMsg() : "unknown";
                throw new ExternalApiException("공공데이터포털 응답 오류: " + msg);
            }
            return extractItems(envelope, itemType);
        } catch (ExternalApiException e) {
            throw e;
        } catch (Exception e) {
            throw new ExternalApiException("공공데이터포털 응답 파싱 실패", e);
        }
    }

    private <T> List<T> extractItems(DataGoKrEnvelope envelope, Class<T> itemType) throws Exception {
        if (envelope.response().body() == null || envelope.response().body().items() == null) {
            return List.of();
        }
        var itemNode = envelope.response().body().items().item();
        if (itemNode == null || itemNode.isNull() || (itemNode.isTextual() && itemNode.asText().isEmpty())) {
            return List.of();
        }
        if (itemNode.isArray()) {
            return objectMapper.readerForListOf(itemType).readValue(itemNode);
        }
        return List.of(objectMapper.treeToValue(itemNode, itemType));
    }

    private RetryTemplate buildRetryTemplate() {
        RetryTemplate template = new RetryTemplate();
        SimpleRetryPolicy retryPolicy = new SimpleRetryPolicy(3, Map.of(ExternalApiException.class, true));
        template.setRetryPolicy(retryPolicy);

        FixedBackOffPolicy backOffPolicy = new ExponentialFixedBackOffPolicy();
        template.setBackOffPolicy(backOffPolicy);
        return template;
    }

    /** 1s → 2s → 4s. 스프링의 ExponentialBackOffPolicy 대신 이름을 명확히 하려고 직접 둔다. */
    private static class ExponentialFixedBackOffPolicy extends FixedBackOffPolicy {
        private int attempt = 0;

        @Override
        public void backOff(org.springframework.retry.backoff.BackOffContext context) {
            attempt++;
            setBackOffPeriod(1000L * (1L << (attempt - 1)));
            super.backOff(context);
        }
    }
}
```

- [ ] **Step 8: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*DataGoKrHttpClientTest*'
```

기대: 2개 테스트 모두 PASS. 두 번째 테스트는 백오프 때문에 약 3초(1s+2s) 소요된다.

- [ ] **Step 9: 커밋**

```bash
git add server/build.gradle server/src/main/resources/application.yml \
  server/src/main/java/com/travelfootsteps/TravelFootstepsApplication.java \
  server/src/main/java/com/travelfootsteps/externaldata \
  server/src/test/java/com/travelfootsteps/support/StubDataGoKrHttpClient.java \
  server/src/test/java/com/travelfootsteps/externaldata
git commit -m "feat(server): 공공데이터포털 공통 HTTP 클라이언트와 재시도 정책"
```

---

### Task 2: 입국허가요건 자연어 파서 — 핵심 구현물

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/visa/ParsedVisaCondition.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaConditionParser.java`
- Test: `server/src/test/java/com/travelfootsteps/visa/VisaConditionParserTest.java`

**Interfaces:**
- Consumes: 없음 (순수 로직, 외부 API·DB에 의존하지 않는다 — 이래야 실제 API 응답 없이도 지금 바로 검증할 수 있다)
- Produces:
  - `ParsedVisaCondition(boolean visaRequired, Integer visaFreeDays, Integer passportValidityMonths)` — `visaFreeDays == null`이면 파싱 실패(Tier B degrade 신호), `passportValidityMonths == null`이면 "특별한 여권 잔여기간 요건을 찾지 못함"(요건 없음으로 간주, degrade 아님)
  - `VisaConditionParser.parse(String visaYn, String visaCn, String evidenceText, String remark)` → `ParsedVisaCondition`. Task 3의 `VisaRequirementCollector`가 이 메서드 하나만 호출한다.

> **왜 `visaFreeDays`와 `passportValidityMonths`의 null 의미가 다른가**: 스펙 §6-①의 판정 로직은 `visa_free_days == null`을 "Tier B 미검증 → 영사관 확인 필요"로 취급한다(최우선 분기). 반면 여권 잔여유효기간은 원문에 언급이 없는 경우가 흔하고("6개월 이상" 요건이 없는 나라가 많음), 그런 경우까지 "미검증"으로 몰면 검증된 국가 대부분이 오탐으로 "영사관 확인 필요"가 된다. 그래서 여권 요건은 "못 찾음 = 요건 없음"으로, 무비자 일수는 "못 찾음 = 모름(안전하게 차단)"으로 다르게 설계한다.

- [ ] **Step 1: 출력 타입 정의**

`server/src/main/java/com/travelfootsteps/visa/ParsedVisaCondition.java`:

```java
package com.travelfootsteps.visa;

public record ParsedVisaCondition(
        boolean visaRequired,
        Integer visaFreeDays,
        Integer passportValidityMonths
) {
}
```

- [ ] **Step 2: 실패하는 테스트 작성 — 실제 공공데이터 문구 우선**

`server/src/test/java/com/travelfootsteps/visa/VisaConditionParserTest.java`:

```java
package com.travelfootsteps.visa;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

class VisaConditionParserTest {

    private final VisaConditionParser parser = new VisaConditionParser();

    @Test
    void 스펙에_인용된_실제_문구_관광_목적_90일_무비자() {
        // docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md §4에 인용된 실제 문구.
        ParsedVisaCondition result = parser.parse("N", "관광 목적 90일 무비자", null, null);

        assertThat(result.visaRequired()).isFalse();
        assertThat(result.visaFreeDays()).isEqualTo(90);
        assertThat(result.passportValidityMonths()).isNull();
    }

    @Test
    void visaYn이_Y이면_비자required_이고_freeDays는_0이다() {
        ParsedVisaCondition result = parser.parse("Y", "관광 목적 비자 필요", null, null);

        assertThat(result.visaRequired()).isTrue();
        assertThat(result.visaFreeDays()).isEqualTo(0);
    }

    @Test
    void 협정에_의한_무비자_문구도_일수를_추출한다() {
        ParsedVisaCondition result = parser.parse("N", "사증면제협정에 의해 30일간 체류 가능", null, null);

        assertThat(result.visaFreeDays()).isEqualTo(30);
    }

    @Test
    void 개월_단위_표기는_30일_기준으로_환산한다() {
        ParsedVisaCondition result = parser.parse("N", "무비자 입국 가능 (체류기간 6개월)", null, null);

        assertThat(result.visaFreeDays()).isEqualTo(180);
    }

    @Test
    void 숫자를_찾을_수_없으면_visaFreeDays는_null이다() {
        ParsedVisaCondition result = parser.parse("N", "자료없음", null, null);

        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void 서로_다른_숫자가_모순되면_ambiguous로_null_처리한다() {
        ParsedVisaCondition result = parser.parse(
                "N", "일반적으로 90일 무비자이나 일부 지역은 30일만 허용", null, null);

        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void 같은_숫자가_반복되면_ambiguous가_아니다() {
        ParsedVisaCondition result = parser.parse(
                "N", "관광 목적 90일 무비자. 상용 목적도 동일하게 90일 적용", null, null);

        assertThat(result.visaFreeDays()).isEqualTo(90);
    }

    @ParameterizedTest
    @CsvSource({
            "여권 유효기간이 입국일로부터 6개월 이상 남아야 함, 6",
            "여권 잔여유효기간 3개월 이상 요구, 3",
            "출국일 기준 여권 유효기간 1개월 이상 필요, 1",
    })
    void 여권_잔여유효기간_문구에서_개월수를_추출한다(String remark, int expectedMonths) {
        ParsedVisaCondition result = parser.parse("N", "관광 목적 90일 무비자", null, remark);

        assertThat(result.passportValidityMonths()).isEqualTo(expectedMonths);
    }

    @Test
    void 여권_요건_언급이_없으면_null이다_요건없음으로_간주() {
        ParsedVisaCondition result = parser.parse("N", "관광 목적 90일 무비자", null, "특이사항 없음");

        assertThat(result.passportValidityMonths()).isNull();
    }

    @Test
    void evidenceText에서도_일수를_찾는다() {
        ParsedVisaCondition result = parser.parse("N", "무비자", "협정에 의해 60일간 체류 허용", null);

        assertThat(result.visaFreeDays()).isEqualTo(60);
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*VisaConditionParserTest*'
```

기대: 컴파일 실패 — `VisaConditionParser` 심볼을 찾을 수 없음.

- [ ] **Step 4: 파서 구현**

`server/src/main/java/com/travelfootsteps/visa/VisaConditionParser.java`:

```java
package com.travelfootsteps.visa;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 외교부 입국허가요건 API의 자연어 필드(gnrl_pspt_visa_cn 등)를
 * {@link ParsedVisaCondition}으로 정규화한다.
 *
 * <p>설계 원칙: 확신이 없으면 null을 반환한다. 잘못된 숫자로 "무비자 45일"이라고
 * 잘못 안내하는 것이, "영사관 확인 필요"라고 보수적으로 안내하는 것보다 훨씬 나쁘다
 * (스펙 §5 "검증되지 않은 데이터로 잘못된 비자 안내를 하지 않는 것이 원칙").
 *
 * <p>패턴은 실제 API 데이터를 확보하는 대로 계속 추가해야 한다. Task 3 착수 시
 * curl로 받은 실제 응답 샘플을 이 클래스의 테스트에 반영한다 (계획서 Global
 * Constraints 참고).
 */
@Component
public class VisaConditionParser {

    private static final List<Pattern> DAY_PATTERNS = List.of(
            Pattern.compile("(\\d+)\\s*일간?")
    );

    private static final List<Pattern> MONTH_AS_STAY_PATTERNS = List.of(
            Pattern.compile("체류\\s*(?:기간)?\\s*[:：]?\\s*(\\d+)\\s*개월"),
            Pattern.compile("(\\d+)\\s*개월\\s*(?:간)?\\s*체류")
    );

    private static final List<Pattern> PASSPORT_VALIDITY_PATTERNS = List.of(
            Pattern.compile("여권\\s*(?:유효기간|잔여\\s*유효기간|잔여기간)[^0-9]{0,10}(\\d+)\\s*개월"),
            Pattern.compile("(?:유효기간|잔여기간)[^0-9]{0,10}(\\d+)\\s*개월[^가-힣]{0,10}(?:이상|남아)")
    );

    public ParsedVisaCondition parse(String visaYn, String visaCn, String evidenceText, String remark) {
        boolean visaRequired = "Y".equalsIgnoreCase(trim(visaYn));

        Integer visaFreeDays = visaRequired
                ? 0
                : extractFreeDays(join(visaCn, evidenceText));

        Integer passportValidityMonths = extractPassportValidityMonths(join(visaCn, remark, evidenceText));

        return new ParsedVisaCondition(visaRequired, visaFreeDays, passportValidityMonths);
    }

    private Integer extractFreeDays(String text) {
        if (text.isBlank()) {
            return null;
        }

        List<Integer> dayMatches = findAll(DAY_PATTERNS, text);
        List<Integer> monthMatches = findAll(MONTH_AS_STAY_PATTERNS, text);

        List<Integer> normalizedDays = new ArrayList<>(dayMatches);
        for (Integer months : monthMatches) {
            normalizedDays.add(months * 30);
        }

        return uniqueOrNull(normalizedDays);
    }

    private Integer extractPassportValidityMonths(String text) {
        if (text.isBlank()) {
            return null;
        }
        List<Integer> matches = findAll(PASSPORT_VALIDITY_PATTERNS, text);
        return uniqueOrNull(matches);
    }

    /** 서로 다른 숫자가 여러 개 나오면 모순으로 보고 null(모름)을 반환한다. */
    private Integer uniqueOrNull(List<Integer> values) {
        if (values.isEmpty()) {
            return null;
        }
        long distinctCount = values.stream().distinct().count();
        if (distinctCount > 1) {
            return null;
        }
        return values.get(0);
    }

    private List<Integer> findAll(List<Pattern> patterns, String text) {
        List<Integer> results = new ArrayList<>();
        for (Pattern pattern : patterns) {
            Matcher matcher = pattern.matcher(text);
            while (matcher.find()) {
                results.add(Integer.parseInt(matcher.group(1)));
            }
        }
        return results;
    }

    private String join(String... parts) {
        StringBuilder sb = new StringBuilder();
        for (String part : parts) {
            if (part != null && !part.isBlank()) {
                sb.append(part).append(' ');
            }
        }
        return sb.toString().trim();
    }

    private String trim(String s) {
        return s == null ? "" : s.trim();
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*VisaConditionParserTest*'
```

기대: 전체 PASS. 만약 `여권_잔여유효기간_문구에서_개월수를_추출한다`의 세 케이스 중 일부가 실패하면, 정규식이 실제 문구의 조사·어순 변형을 못 잡는 것이다 — 패턴을 추가하되 기존 패턴을 제거하지 않는다(실제 데이터에 어떤 변형이 있을지 모르므로 패턴은 계속 누적한다).

- [ ] **Step 6: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/visa/ParsedVisaCondition.java \
  server/src/main/java/com/travelfootsteps/visa/VisaConditionParser.java \
  server/src/test/java/com/travelfootsteps/visa/VisaConditionParserTest.java
git commit -m "feat(server): 입국허가요건 자연어 파서"
```

---

### Task 3: 입국허가요건 수집 — `visa_requirement` 테이블과 단건 수집기

**Files:**
- Create: `server/src/main/resources/db/migration/V2__visa_requirement.sql`
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaRequirement.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaRequirementRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/EntranceVisaApiItem.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/EntranceVisaClient.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaRequirementCollector.java`
- Test: `server/src/test/java/com/travelfootsteps/visa/VisaRequirementCollectorTest.java`

**Interfaces:**
- Consumes: Task 1의 `DataGoKrHttpClient`, Task 2의 `VisaConditionParser`, Phase 0의 `CountryRepository`
- Produces:
  - 테이블 `visa_requirement` (컬럼은 스펙 §7과 동일)
  - `VisaRequirement` 엔티티 — getter 전부 + `isVerified()`, 패키지 프라이빗 `applyCollectedData(...)`(파싱 결과 반영), `markSourceRefreshedOnly(...)`(검증된 행의 원문만 갱신)
  - `VisaRequirementRepository.findByCountryIdAndPassportType(Long, String)`
  - `VisaRequirementCollector.collectOne(Country country)` — 성공하면 `visa_requirement` 행을 upsert, 실패(재시도 소진)하면 예외를 잡아 로그만 남기고 조용히 반환한다(배치가 계속 진행되도록). Task 4의 스케줄러가 국가 목록을 순회하며 이 메서드를 호출한다.

> **실제 API 응답 확인 필요**: 아래 `EntranceVisaClient`의 경로(`/1262000/EntranceVisaService2/getEntranceVisaList2`)와 파라미터(`cond[country_iso_alp2::EQ]`)는 Phase 0 Task 2 Step 2가 검증하기로 한 것과 동일한 값이다. 이 태스크를 시작하기 전에 Phase 0 Task 2가 완료되어 실제 호출이 성공하는지 먼저 확인한다. 활용가이드 문서의 실제 값이 다르면 `EntranceVisaClient`의 상수만 바꾸면 된다 — 나머지 코드는 영향받지 않는다.

- [ ] **Step 1: 마이그레이션 작성**

`server/src/main/resources/db/migration/V2__visa_requirement.sql`:

```sql
CREATE TABLE visa_requirement (
    id                          BIGSERIAL PRIMARY KEY,
    country_id                  BIGINT NOT NULL REFERENCES country(id),
    passport_type               VARCHAR(10) NOT NULL DEFAULT 'GENERAL',
    visa_required                BOOLEAN NOT NULL,
    visa_free_days                INTEGER,
    passport_validity_months      INTEGER,
    raw_text                       TEXT,
    evidence_text                  TEXT,
    remark                          TEXT,
    source_fetched_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified                        BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT visa_requirement_passport_type_check
        CHECK (passport_type IN ('GENERAL', 'OFFICIAL', 'DIPLOMATIC')),
    CONSTRAINT visa_requirement_country_passport_unique UNIQUE (country_id, passport_type)
);

CREATE INDEX idx_visa_requirement_country ON visa_requirement (country_id);
```

- [ ] **Step 2: API 응답 매핑 레코드**

`server/src/main/java/com/travelfootsteps/visa/EntranceVisaApiItem.java` — 필드명은 API 원문 그대로 두고 Jackson이 스네이크→카멜 매핑 없이 그대로 읽게 한다(응답 필드명 자체가 스네이크·약어라서 자동 변환 규칙에 맞지 않는다).

```java
package com.travelfootsteps.visa;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record EntranceVisaApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("country_nm") String countryNm,
        @JsonProperty("gnrl_pspt_visa_yn") String gnrlPsptVisaYn,
        @JsonProperty("gnrl_pspt_visa_cn") String gnrlPsptVisaCn,
        @JsonProperty("nvisa_entry_evdc_cn") String nvisaEntryEvdcCn,
        @JsonProperty("remark") String remark
) {
}
```

- [ ] **Step 3: API 클라이언트**

`server/src/main/java/com/travelfootsteps/visa/EntranceVisaClient.java`:

```java
package com.travelfootsteps.visa;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.Optional;

@Component
public class EntranceVisaClient {

    private static final String PATH = "/1262000/EntranceVisaService2/getEntranceVisaList2";

    private final DataGoKrHttpClient httpClient;

    public EntranceVisaClient(DataGoKrHttpClient httpClient) {
        this.httpClient = httpClient;
    }

    public Optional<EntranceVisaApiItem> fetch(String countryIsoAlpha2) {
        List<EntranceVisaApiItem> items = httpClient.getItems(
                PATH,
                Map.of(
                        "numOfRows", "10",
                        "pageNo", "1",
                        "cond[country_iso_alp2::EQ]", countryIsoAlpha2
                ),
                EntranceVisaApiItem.class
        );
        return items.stream().findFirst();
    }
}
```

- [ ] **Step 4: 엔티티**

`server/src/main/java/com/travelfootsteps/visa/VisaRequirement.java`:

```java
package com.travelfootsteps.visa;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

@Entity
@Table(name = "visa_requirement")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class VisaRequirement {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(name = "passport_type", nullable = false, length = 10)
    private String passportType;

    @Column(name = "visa_required", nullable = false)
    private boolean visaRequired;

    @Column(name = "visa_free_days")
    private Integer visaFreeDays;

    @Column(name = "passport_validity_months")
    private Integer passportValidityMonths;

    @Column(name = "raw_text", columnDefinition = "TEXT")
    private String rawText;

    @Column(name = "evidence_text", columnDefinition = "TEXT")
    private String evidenceText;

    @Column(columnDefinition = "TEXT")
    private String remark;

    @Column(name = "source_fetched_at", nullable = false)
    private OffsetDateTime sourceFetchedAt;

    @Column(nullable = false)
    private boolean verified;

    public static VisaRequirement newUnverified(Long countryId, String passportType) {
        VisaRequirement v = new VisaRequirement();
        v.countryId = countryId;
        v.passportType = passportType;
        v.verified = false;
        return v;
    }

    /** 파싱 결과와 원문을 전부 갱신한다. verified=true인 행에는 호출하지 않는다. */
    public void applyCollectedData(ParsedVisaCondition parsed, String rawText, String evidenceText,
                                    String remark, OffsetDateTime fetchedAt) {
        this.visaRequired = parsed.visaRequired();
        this.visaFreeDays = parsed.visaFreeDays();
        this.passportValidityMonths = parsed.passportValidityMonths();
        this.rawText = rawText;
        this.evidenceText = evidenceText;
        this.remark = remark;
        this.sourceFetchedAt = fetchedAt;
    }

    /** verified=true인 Tier A 행은 판정 필드를 건드리지 않고 원문 참고자료만 최신화한다. */
    public void refreshSourceOnly(String rawText, String evidenceText, String remark,
                                   OffsetDateTime fetchedAt) {
        this.rawText = rawText;
        this.evidenceText = evidenceText;
        this.remark = remark;
        this.sourceFetchedAt = fetchedAt;
    }
}
```

- [ ] **Step 5: 리포지토리**

`server/src/main/java/com/travelfootsteps/visa/VisaRequirementRepository.java`:

```java
package com.travelfootsteps.visa;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface VisaRequirementRepository extends JpaRepository<VisaRequirement, Long> {
    Optional<VisaRequirement> findByCountryIdAndPassportType(Long countryId, String passportType);
}
```

- [ ] **Step 6: 실패하는 수집기 테스트**

`server/src/test/java/com/travelfootsteps/visa/VisaRequirementCollectorTest.java` — Testcontainers로 실제 스키마를 검증하되, 외부 API는 `EntranceVisaClient`를 목(mock)으로 대체한다.

```java
package com.travelfootsteps.visa;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Import;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@SpringBootTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
@Import(VisaRequirementCollectorTest.TestBeans.class)
class VisaRequirementCollectorTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        EntranceVisaClient entranceVisaClient() {
            return mock(EntranceVisaClient.class);
        }
    }

    @Autowired CountryRepository countryRepository;
    @Autowired VisaRequirementRepository visaRequirementRepository;
    @Autowired VisaRequirementCollector collector;
    @Autowired EntranceVisaClient entranceVisaClient;

    @Test
    void 첫_수집은_새_행을_만들고_파싱_결과를_저장한다() {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        when(entranceVisaClient.fetch("VN")).thenReturn(Optional.of(new EntranceVisaApiItem(
                "VN", "베트남", "N", "관광 목적 45일 무비자", null, null)));

        collector.collectOne(vietnam);

        VisaRequirement saved = visaRequirementRepository
                .findByCountryIdAndPassportType(vietnam.getId(), "GENERAL").orElseThrow();
        assertThat(saved.isVisaRequired()).isFalse();
        assertThat(saved.getVisaFreeDays()).isEqualTo(45);
        assertThat(saved.isVerified()).isFalse();
    }

    @Test
    void verified_true인_행은_판정_필드를_덮어쓰지_않는다() {
        Country japan = countryRepository.findByIsoAlpha2("JP").orElseThrow();
        VisaRequirement verified = VisaRequirement.newUnverified(japan.getId(), "GENERAL");
        verified.applyCollectedData(new ParsedVisaCondition(false, 90, null),
                "원문", null, null, java.time.OffsetDateTime.now());
        // 수기 검증되었다고 가정 — 리플렉션 대신 저장 후 검증 플래그를 세우는 테스트 전용 헬퍼가 없으므로
        // verified는 이 테스트에서 직접 SQL로 세운다.
        visaRequirementRepository.save(verified);
        countryRepository.flush();
        jakarta.persistence.EntityManager em = null; // 아래에서 대체 확인

        when(entranceVisaClient.fetch("JP")).thenReturn(Optional.of(new EntranceVisaApiItem(
                "JP", "일본", "N", "관광 목적 15일 무비자로 변경됨(오수집 가정)", null, null)));

        // verified 플래그를 켜기 위해 리포지토리 저장 후 네이티브 갱신을 쓴다.
        markVerified(verified.getId());

        collector.collectOne(japan);

        VisaRequirement after = visaRequirementRepository.findById(verified.getId()).orElseThrow();
        assertThat(after.getVisaFreeDays()).isEqualTo(90); // 그대로 유지 — 15로 바뀌지 않음
        assertThat(after.getRawText()).contains("15일"); // 원문 참고자료는 갱신됨
    }

    @org.springframework.beans.factory.annotation.Autowired
    private jakarta.persistence.EntityManager entityManager;

    private void markVerified(Long id) {
        entityManager.createNativeQuery("UPDATE visa_requirement SET verified = true WHERE id = :id")
                .setParameter("id", id)
                .executeUpdate();
        entityManager.clear();
    }

    @Test
    void 재시도_소진_예외는_배치를_중단시키지_않고_기존_행을_그대로_둔다() {
        Country france = countryRepository.findByIsoAlpha2("FR").orElseThrow();
        when(entranceVisaClient.fetch("FR"))
                .thenThrow(new com.travelfootsteps.externaldata.ExternalApiException("일시 장애"));

        collector.collectOne(france); // 예외를 던지지 않아야 한다

        assertThat(visaRequirementRepository.findByCountryIdAndPassportType(france.getId(), "GENERAL"))
                .isEmpty();
    }
}
```

> 두 번째 테스트는 `verified` 플래그를 세울 공개 API가 없다는 것을 드러낸다 — 이 계획에서는 의도적으로 만들지 않는다(Global Constraints 참고). 테스트에서만 네이티브 쿼리로 우회한다.

- [ ] **Step 7: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*VisaRequirementCollectorTest*'
```

기대: 컴파일 실패 — `VisaRequirementCollector` 심볼을 찾을 수 없음.

- [ ] **Step 8: 수집기 구현**

`server/src/main/java/com/travelfootsteps/visa/VisaRequirementCollector.java`:

```java
package com.travelfootsteps.visa;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.externaldata.ExternalApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Optional;

@Slf4j
@Component
@RequiredArgsConstructor
public class VisaRequirementCollector {

    private static final String PASSPORT_TYPE_GENERAL = "GENERAL";

    private final EntranceVisaClient client;
    private final VisaConditionParser parser;
    private final VisaRequirementRepository repository;

    @Transactional
    public void collectOne(Country country) {
        Optional<EntranceVisaApiItem> apiItem;
        try {
            apiItem = client.fetch(country.getIsoAlpha2());
        } catch (ExternalApiException e) {
            log.warn("입국허가요건 수집 실패, 건너뜀: country={}, reason={}",
                    country.getIsoAlpha2(), e.getMessage());
            return;
        }

        if (apiItem.isEmpty()) {
            log.info("입국허가요건 응답 없음: country={}", country.getIsoAlpha2());
            return;
        }

        EntranceVisaApiItem item = apiItem.get();
        VisaRequirement requirement = repository
                .findByCountryIdAndPassportType(country.getId(), PASSPORT_TYPE_GENERAL)
                .orElseGet(() -> VisaRequirement.newUnverified(country.getId(), PASSPORT_TYPE_GENERAL));

        OffsetDateTime now = OffsetDateTime.now();
        if (requirement.isVerified()) {
            requirement.refreshSourceOnly(item.gnrlPsptVisaCn(), item.nvisaEntryEvdcCn(), item.remark(), now);
        } else {
            ParsedVisaCondition parsed = parser.parse(
                    item.gnrlPsptVisaYn(), item.gnrlPsptVisaCn(), item.nvisaEntryEvdcCn(), item.remark());
            requirement.applyCollectedData(parsed, item.gnrlPsptVisaCn(), item.nvisaEntryEvdcCn(),
                    item.remark(), now);
        }

        repository.save(requirement);
    }
}
```

- [ ] **Step 9: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*VisaRequirementCollectorTest*'
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 10: 커밋**

```bash
git add server/src/main/resources/db/migration/V2__visa_requirement.sql \
  server/src/main/java/com/travelfootsteps/visa
git add server/src/test/java/com/travelfootsteps/visa/VisaRequirementCollectorTest.java
git commit -m "feat(server): 입국허가요건 수집기와 visa_requirement 테이블"
```

---

### Task 4: 여행경보·재외공관 수집 + 일 1회 배치 스케줄러

**Files:**
- Create: `server/src/main/resources/db/migration/V3__travel_alert_embassy.sql`
- Create: `server/src/main/java/com/travelfootsteps/alert/{TravelAlert,TravelAlertRepository,TravelAlertApiItem,TravelAlertClient,TravelAlertCollector,TravelAlertResponse,TravelAlertController}.java`
- Create: `server/src/main/java/com/travelfootsteps/embassy/{Embassy,EmbassyRepository,EmbassyApiItem,EmbassyClient,EmbassyCollector,EmbassyResponse,EmbassyController}.java`
- Create: `server/src/main/java/com/travelfootsteps/batch/DailyDataCollectionScheduler.java`
- Test: `server/src/test/java/com/travelfootsteps/alert/TravelAlertControllerTest.java`
- Test: `server/src/test/java/com/travelfootsteps/embassy/EmbassyControllerTest.java`
- Test: `server/src/test/java/com/travelfootsteps/batch/DailyDataCollectionSchedulerTest.java`

**Interfaces:**
- Consumes: Task 1의 `DataGoKrHttpClient`, Task 3의 `VisaRequirementCollector`, Phase 0의 `CountryRepository`/`TokenVerifier`
- Produces:
  - `GET /api/countries/{iso2}/alerts` → `200 [{id, level, region, title, issuedAt}]` (Plan F 계약)
  - `GET /api/countries/{iso2}/embassies` → `200 [{id, type, name, lat, lng, phone, emergencyPhone, address}]` (Plan F 계약)
  - `DailyDataCollectionScheduler.runDaily()` — `@Scheduled(cron = "0 0 3 * * *", zone = "Asia/Seoul")`가 호출하는, 테스트에서 직접 호출 가능한 public 메서드. 전 국가에 대해 비자·경보·공관 세 수집기를 순서대로 돌린다.

- [ ] **Step 1: 마이그레이션 작성**

`server/src/main/resources/db/migration/V3__travel_alert_embassy.sql`:

```sql
CREATE TABLE travel_alert (
    id         BIGSERIAL PRIMARY KEY,
    country_id BIGINT NOT NULL REFERENCES country(id),
    level      INTEGER NOT NULL,
    region     VARCHAR(100),
    title      VARCHAR(255) NOT NULL,
    issued_at  TIMESTAMPTZ NOT NULL,
    -- level 0 = UNKNOWN(파싱 실패/미확인). 1(안전)로 낙관 처리하지 않는다 — 2026-09-12 리뷰 반영.
    CONSTRAINT travel_alert_level_check CHECK (level BETWEEN 0 AND 4)
);

CREATE INDEX idx_travel_alert_country ON travel_alert (country_id);

CREATE TABLE embassy (
    id              BIGSERIAL PRIMARY KEY,
    country_id      BIGINT NOT NULL REFERENCES country(id),
    type            VARCHAR(20) NOT NULL,
    name            VARCHAR(255) NOT NULL,
    lat             DOUBLE PRECISION NOT NULL,
    lng             DOUBLE PRECISION NOT NULL,
    phone           VARCHAR(50),
    emergency_phone VARCHAR(50),
    address         VARCHAR(255)
);

CREATE INDEX idx_embassy_country ON embassy (country_id);
```

- [ ] **Step 2: 여행경보 도메인 — 엔티티/리포지토리/API 클라이언트**

`server/src/main/java/com/travelfootsteps/alert/TravelAlert.java`:

```java
package com.travelfootsteps.alert;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

@Entity
@Table(name = "travel_alert")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TravelAlert {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(nullable = false)
    private int level;

    @Column(length = 100)
    private String region;

    @Column(nullable = false, length = 255)
    private String title;

    @Column(name = "issued_at", nullable = false)
    private OffsetDateTime issuedAt;

    @Builder
    public TravelAlert(Long countryId, int level, String region, String title, OffsetDateTime issuedAt) {
        this.countryId = countryId;
        this.level = level;
        this.region = region;
        this.title = title;
        this.issuedAt = issuedAt;
    }
}
```

`server/src/main/java/com/travelfootsteps/alert/TravelAlertRepository.java`:

```java
package com.travelfootsteps.alert;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TravelAlertRepository extends JpaRepository<TravelAlert, Long> {
    List<TravelAlert> findByCountryIdOrderByIssuedAtDesc(Long countryId);
    void deleteByCountryId(Long countryId);
}
```

`server/src/main/java/com/travelfootsteps/alert/TravelAlertApiItem.java`:

```java
package com.travelfootsteps.alert;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record TravelAlertApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("alarm_lvl") String alarmLevel,
        @JsonProperty("remark") String region,
        @JsonProperty("title") String title,
        @JsonProperty("wrt_dt") String issuedAt
) {
}
```

`server/src/main/java/com/travelfootsteps/alert/TravelAlertClient.java`:

```java
package com.travelfootsteps.alert;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
public class TravelAlertClient {

    private static final String PATH = "/1262000/TravelAlarmService2/getTravelAlarmList2";

    private final DataGoKrHttpClient httpClient;

    public TravelAlertClient(DataGoKrHttpClient httpClient) {
        this.httpClient = httpClient;
    }

    public List<TravelAlertApiItem> fetch(String countryIsoAlpha2) {
        return httpClient.getItems(
                PATH,
                Map.of("numOfRows", "20", "pageNo", "1", "cond[country_iso_alp2::EQ]", countryIsoAlpha2),
                TravelAlertApiItem.class
        );
    }
}
```

`server/src/main/java/com/travelfootsteps/alert/TravelAlertCollector.java` — 국가당 "현재 상태"만 의미가 있으므로, 기존 행을 지우고 새로 넣는 **교체(replace) 전략**을 쓴다(비자처럼 단일 행 upsert가 아니라 여러 건이 나올 수 있어서 upsert 키가 애매하다).

```java
package com.travelfootsteps.alert;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.externaldata.ExternalApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;

@Slf4j
@Component
@RequiredArgsConstructor
public class TravelAlertCollector {

    private static final DateTimeFormatter SOURCE_FORMAT = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final TravelAlertClient client;
    private final TravelAlertRepository repository;

    @Transactional
    public void collectOne(Country country) {
        try {
            var items = client.fetch(country.getIsoAlpha2());
            repository.deleteByCountryId(country.getId());
            for (TravelAlertApiItem item : items) {
                repository.save(TravelAlert.builder()
                        .countryId(country.getId())
                        .level(parseLevel(item.alarmLevel()))
                        .region(item.region())
                        .title(item.title())
                        .issuedAt(parseIssuedAt(item.issuedAt()))
                        .build());
            }
        } catch (ExternalApiException e) {
            log.warn("여행경보 수집 실패, 건너뜀: country={}, reason={}", country.getIsoAlpha2(), e.getMessage());
        }
    }

    private int parseLevel(String raw) {
        try {
            return Integer.parseInt(raw.trim());
        } catch (NumberFormatException e) {
            // 파싱 실패를 1단계(안전)로 낙관 처리하면 실제로는 위험도가 높을 수도 있는 국가를
            // "안전"으로 잘못 보여주게 된다. 0(UNKNOWN)으로 남겨 앱이 "확인 필요"로 구분해 표시하게 한다.
            return 0; // UNKNOWN — 2026-09-12 리뷰 반영
        }
    }

    private OffsetDateTime parseIssuedAt(String raw) {
        try {
            return java.time.LocalDate.parse(raw, SOURCE_FORMAT).atStartOfDay(java.time.ZoneOffset.UTC).toOffsetDateTime();
        } catch (DateTimeParseException | NullPointerException e) {
            return OffsetDateTime.now();
        }
    }
}
```

`server/src/main/java/com/travelfootsteps/alert/TravelAlertResponse.java`:

```java
package com.travelfootsteps.alert;

import java.time.OffsetDateTime;

public record TravelAlertResponse(Long id, int level, String region, String title, OffsetDateTime issuedAt) {
    public static TravelAlertResponse from(TravelAlert alert) {
        return new TravelAlertResponse(alert.getId(), alert.getLevel(), alert.getRegion(),
                alert.getTitle(), alert.getIssuedAt());
    }
}
```

- [ ] **Step 3: 실패하는 컨트롤러 테스트**

`server/src/test/java/com/travelfootsteps/alert/TravelAlertControllerTest.java`:

```java
package com.travelfootsteps.alert;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(TravelAlertControllerTest.TestBeans.class)
class TravelAlertControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired CountryRepository countryRepository;
    @Autowired TravelAlertRepository travelAlertRepository;

    @Test
    void 국가의_여행경보_목록을_최신순으로_반환한다() throws Exception {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        travelAlertRepository.save(TravelAlert.builder()
                .countryId(vietnam.getId()).level(2).region("전역").title("여행자제")
                .issuedAt(OffsetDateTime.now()).build());

        mockMvc.perform(get("/api/countries/VN/alerts").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].level").value(2))
                .andExpect(jsonPath("$[0].title").value("여행자제"));
    }

    @Test
    void 존재하지_않는_국가는_404() throws Exception {
        mockMvc.perform(get("/api/countries/ZZ/alerts").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }
}
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*TravelAlertControllerTest*'
```

기대: 컴파일 실패 — `TravelAlertController` 심볼을 찾을 수 없음.

- [ ] **Step 5: 컨트롤러 구현**

`server/src/main/java/com/travelfootsteps/alert/TravelAlertController.java`:

```java
package com.travelfootsteps.alert;

import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.List;

@RestController
@RequestMapping("/api/countries/{iso2}/alerts")
@RequiredArgsConstructor
public class TravelAlertController {

    private final CountryRepository countryRepository;
    private final TravelAlertRepository travelAlertRepository;

    @GetMapping
    public List<TravelAlertResponse> list(@PathVariable String iso2) {
        var country = countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
        return travelAlertRepository.findByCountryIdOrderByIssuedAtDesc(country.getId())
                .stream().map(TravelAlertResponse::from).toList();
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*TravelAlertControllerTest*'
```

기대: 2개 테스트 PASS.

- [ ] **Step 7: 재외공관 도메인 — 여행경보와 동일한 패턴으로 구현**

`server/src/main/java/com/travelfootsteps/embassy/Embassy.java`:

```java
package com.travelfootsteps.embassy;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "embassy")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Embassy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(nullable = false, length = 20)
    private String type;

    @Column(nullable = false, length = 255)
    private String name;

    @Column(nullable = false)
    private double lat;

    @Column(nullable = false)
    private double lng;

    @Column(length = 50)
    private String phone;

    @Column(name = "emergency_phone", length = 50)
    private String emergencyPhone;

    @Column(length = 255)
    private String address;

    @Builder
    public Embassy(Long countryId, String type, String name, double lat, double lng,
                    String phone, String emergencyPhone, String address) {
        this.countryId = countryId;
        this.type = type;
        this.name = name;
        this.lat = lat;
        this.lng = lng;
        this.phone = phone;
        this.emergencyPhone = emergencyPhone;
        this.address = address;
    }
}
```

`server/src/main/java/com/travelfootsteps/embassy/EmbassyRepository.java`:

```java
package com.travelfootsteps.embassy;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EmbassyRepository extends JpaRepository<Embassy, Long> {
    List<Embassy> findByCountryId(Long countryId);
    void deleteByCountryId(Long countryId);
}
```

`server/src/main/java/com/travelfootsteps/embassy/EmbassyApiItem.java`:

```java
package com.travelfootsteps.embassy;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record EmbassyApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("mission_type") String type,
        @JsonProperty("mission_nm") String name,
        @JsonProperty("lat") Double lat,
        @JsonProperty("lng") Double lng,
        @JsonProperty("tel_no") String phone,
        @JsonProperty("emgcy_tel_no") String emergencyPhone,
        @JsonProperty("addr") String address
) {
}
```

`server/src/main/java/com/travelfootsteps/embassy/EmbassyClient.java`:

```java
package com.travelfootsteps.embassy;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
public class EmbassyClient {

    private static final String PATH = "/1262000/EmbassyService2/getEmbassyList2";

    private final DataGoKrHttpClient httpClient;

    public EmbassyClient(DataGoKrHttpClient httpClient) {
        this.httpClient = httpClient;
    }

    public List<EmbassyApiItem> fetch(String countryIsoAlpha2) {
        return httpClient.getItems(
                PATH,
                Map.of("numOfRows", "20", "pageNo", "1", "cond[country_iso_alp2::EQ]", countryIsoAlpha2),
                EmbassyApiItem.class
        );
    }
}
```

`server/src/main/java/com/travelfootsteps/embassy/EmbassyCollector.java`:

```java
package com.travelfootsteps.embassy;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.externaldata.ExternalApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Component
@RequiredArgsConstructor
public class EmbassyCollector {

    private final EmbassyClient client;
    private final EmbassyRepository repository;

    @Transactional
    public void collectOne(Country country) {
        try {
            var items = client.fetch(country.getIsoAlpha2());
            repository.deleteByCountryId(country.getId());
            for (EmbassyApiItem item : items) {
                if (item.lat() == null || item.lng() == null) {
                    continue; // 좌표 없는 항목은 지도 핀을 만들 수 없으므로 건너뜀
                }
                repository.save(Embassy.builder()
                        .countryId(country.getId())
                        .type(item.type() != null ? item.type() : "대사관")
                        .name(item.name())
                        .lat(item.lat())
                        .lng(item.lng())
                        .phone(item.phone())
                        .emergencyPhone(item.emergencyPhone())
                        .address(item.address())
                        .build());
            }
        } catch (ExternalApiException e) {
            log.warn("재외공관 수집 실패, 건너뜀: country={}, reason={}", country.getIsoAlpha2(), e.getMessage());
        }
    }
}
```

`server/src/main/java/com/travelfootsteps/embassy/EmbassyResponse.java`:

```java
package com.travelfootsteps.embassy;

public record EmbassyResponse(Long id, String type, String name, double lat, double lng,
                               String phone, String emergencyPhone, String address) {
    public static EmbassyResponse from(Embassy embassy) {
        return new EmbassyResponse(embassy.getId(), embassy.getType(), embassy.getName(),
                embassy.getLat(), embassy.getLng(), embassy.getPhone(),
                embassy.getEmergencyPhone(), embassy.getAddress());
    }
}
```

`server/src/main/java/com/travelfootsteps/embassy/EmbassyController.java`:

```java
package com.travelfootsteps.embassy;

import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@RestController
@RequestMapping("/api/countries/{iso2}/embassies")
@RequiredArgsConstructor
public class EmbassyController {

    private final CountryRepository countryRepository;
    private final EmbassyRepository embassyRepository;

    @GetMapping
    public List<EmbassyResponse> list(@PathVariable String iso2) {
        var country = countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
        return embassyRepository.findByCountryId(country.getId())
                .stream().map(EmbassyResponse::from).toList();
    }
}
```

`server/src/test/java/com/travelfootsteps/embassy/EmbassyControllerTest.java`는 `TravelAlertControllerTest`와 동일한 구조로 작성한다 (필드만 공관에 맞게 교체). 아래는 전체 코드다.

```java
package com.travelfootsteps.embassy;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(EmbassyControllerTest.TestBeans.class)
class EmbassyControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired CountryRepository countryRepository;
    @Autowired EmbassyRepository embassyRepository;

    @Test
    void 국가의_재외공관_목록을_반환한다() throws Exception {
        Country japan = countryRepository.findByIsoAlpha2("JP").orElseThrow();
        embassyRepository.save(Embassy.builder()
                .countryId(japan.getId()).type("대사관").name("주일본 대한민국 대사관")
                .lat(35.6762).lng(139.7503).phone("+81-3-0000-0000")
                .emergencyPhone("+81-90-0000-0000").address("Tokyo").build());

        mockMvc.perform(get("/api/countries/JP/embassies").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("주일본 대한민국 대사관"))
                .andExpect(jsonPath("$[0].lat").value(35.6762));
    }

    @Test
    void 존재하지_않는_국가는_404() throws Exception {
        mockMvc.perform(get("/api/countries/ZZ/embassies").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }
}
```

- [ ] **Step 8: 재외공관 테스트 실행**

```bash
cd server && ./gradlew test --tests '*EmbassyControllerTest*'
```

기대: 컴파일 실패 확인(위 파일들 아직 없다면) → 구현 → PASS. Step 7의 코드를 모두 작성한 뒤 실행한다.

- [ ] **Step 9: 배치 스케줄러 — 실패하는 테스트**

`server/src/test/java/com/travelfootsteps/batch/DailyDataCollectionSchedulerTest.java`:

```java
package com.travelfootsteps.batch;

import com.travelfootsteps.alert.TravelAlertCollector;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.embassy.EmbassyCollector;
import com.travelfootsteps.visa.VisaRequirementCollector;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DailyDataCollectionSchedulerTest {

    @Mock CountryRepository countryRepository;
    @Mock VisaRequirementCollector visaCollector;
    @Mock TravelAlertCollector alertCollector;
    @Mock EmbassyCollector embassyCollector;

    @InjectMocks
    DailyDataCollectionScheduler scheduler;

    @Test
    void 모든_국가에_대해_세_수집기를_전부_호출한다() {
        Country vn = mockCountry("VN");
        Country jp = mockCountry("JP");
        when(countryRepository.findAll()).thenReturn(List.of(vn, jp));

        scheduler.runDaily();

        verify(visaCollector, times(1)).collectOne(vn);
        verify(visaCollector, times(1)).collectOne(jp);
        verify(alertCollector, times(1)).collectOne(vn);
        verify(embassyCollector, times(1)).collectOne(vn);
    }

    @Test
    void 한_국가에서_예외가_나도_나머지_국가는_계속_처리한다() {
        Country vn = mockCountry("VN");
        Country jp = mockCountry("JP");
        when(countryRepository.findAll()).thenReturn(List.of(vn, jp));
        org.mockito.Mockito.doThrow(new RuntimeException("예상치 못한 오류"))
                .when(visaCollector).collectOne(vn);

        scheduler.runDaily();

        verify(visaCollector, times(1)).collectOne(jp);
        verify(alertCollector, times(1)).collectOne(jp);
    }

    private Country mockCountry(String iso2) {
        Country country = org.mockito.Mockito.mock(Country.class);
        when(country.getIsoAlpha2()).thenReturn(iso2);
        return country;
    }
}
```

> 두 번째 테스트는 각 수집기(`collectOne`)가 이미 자기 내부에서 `ExternalApiException`을 흡수하지만(Task 3, Step 8/Task 4), 예상치 못한 다른 예외(NPE 등)까지 배치 전체를 죽이지 않도록 스케줄러 레벨에서도 한 번 더 방어한다는 것을 검증한다.

- [ ] **Step 10: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*DailyDataCollectionSchedulerTest*'
```

기대: 컴파일 실패 — `DailyDataCollectionScheduler` 심볼을 찾을 수 없음.

- [ ] **Step 11: 스케줄러 구현**

`server/src/main/java/com/travelfootsteps/batch/DailyDataCollectionScheduler.java`:

```java
package com.travelfootsteps.batch;

import com.travelfootsteps.alert.TravelAlertCollector;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.embassy.EmbassyCollector;
import com.travelfootsteps.visa.VisaRequirementCollector;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class DailyDataCollectionScheduler {

    private final CountryRepository countryRepository;
    private final VisaRequirementCollector visaRequirementCollector;
    private final TravelAlertCollector travelAlertCollector;
    private final EmbassyCollector embassyCollector;

    /** 매일 03:00(KST) 실행. 전 국가 Tier A/B 구분 없이 순회하되, Tier A는
     * VisaRequirementCollector 내부에서 verified 플래그로 판정 필드 보존을 처리한다. */
    @Scheduled(cron = "0 0 3 * * *", zone = "Asia/Seoul")
    public void runDaily() {
        var countries = countryRepository.findAll();
        log.info("일일 공공데이터 수집 시작: {}개국", countries.size());

        for (Country country : countries) {
            collectSafely(country, "visa", () -> visaRequirementCollector.collectOne(country));
            collectSafely(country, "alert", () -> travelAlertCollector.collectOne(country));
            collectSafely(country, "embassy", () -> embassyCollector.collectOne(country));
        }

        log.info("일일 공공데이터 수집 종료");
    }

    private void collectSafely(Country country, String label, Runnable task) {
        try {
            task.run();
        } catch (Exception e) {
            log.error("{} 수집 중 예상치 못한 오류, 다음 국가로 진행: country={}", label, country.getIsoAlpha2(), e);
        }
    }
}
```

- [ ] **Step 12: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*DailyDataCollectionSchedulerTest*'
```

기대: 2개 테스트 PASS.

- [ ] **Step 13: 전체 회귀 테스트 + 실서버 스모크**

```bash
cd server && ./gradlew test
```

기대: 전체 PASS. Docker Postgres가 떠 있다면 `./gradlew bootRun` 후 `curl http://localhost:8080/api/countries/VN/alerts`로 401(토큰 없음)을 확인해도 좋다.

- [ ] **Step 14: 커밋**

```bash
git add server/src/main/resources/db/migration/V3__travel_alert_embassy.sql \
  server/src/main/java/com/travelfootsteps/alert \
  server/src/main/java/com/travelfootsteps/embassy \
  server/src/main/java/com/travelfootsteps/batch \
  server/src/test/java/com/travelfootsteps/alert \
  server/src/test/java/com/travelfootsteps/embassy \
  server/src/test/java/com/travelfootsteps/batch
git commit -m "feat(server): 여행경보·재외공관 수집기와 일일 배치 스케줄러"
```

---

### Task 5: 비자 판정 규칙 엔진 + 역산 일정 생성기

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaVerdict.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaJudgement.java`
- Create: `server/src/main/java/com/travelfootsteps/visa/VisaJudgementService.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/ScheduleGenerator.java`
- Test: `server/src/test/java/com/travelfootsteps/visa/VisaJudgementServiceTest.java`
- Test: `server/src/test/java/com/travelfootsteps/trip/ScheduleGeneratorTest.java`

**Interfaces:**
- Consumes: Task 3의 `VisaRequirement` 엔티티 (DB 접근 없이 순수 도메인 로직 — `VisaRequirementRepository`를 주입받지 않는다. 호출부인 Task 6의 `TripController`가 리포지토리 조회 후 엔티티를 넘긴다)
- Produces:
  - `VisaVerdict` enum — `VISA_FREE_OK("VISA_FREE_OK")`, `VISA_FREE_EXCEEDED("VISA_FREE_EXCEEDED")`, `VISA_REQUIRED("VISA_REQUIRED")`, `UNVERIFIED("UNVERIFIED")`. **`wireValue()`가 Plan B의 `VisaVerdict.wireValue`와 문자 그대로 일치해야 한다.**
  - `VisaJudgement(VisaVerdict verdict, int stayDays, Integer visaFreeDays, boolean passportOk, Integer passportValidityMonths, Integer passportShortfallDays)`
  - `VisaJudgementService.judge(VisaRequirement requirement /* nullable */, LocalDate departDate, LocalDate returnDate, LocalDate passportExpiry)` → `VisaJudgement`
  - `ScheduleGenerator.generate(LocalDate departDate, VisaJudgement judgement)` → `List<GeneratedTask>`(`record GeneratedTask(String title, LocalDate dueDate)`). Task 6이 이 목록으로 `trip_task` 행을 만든다.

- [ ] **Step 1: verdict enum**

`server/src/main/java/com/travelfootsteps/visa/VisaVerdict.java`:

```java
package com.travelfootsteps.visa;

public enum VisaVerdict {
    VISA_FREE_OK("VISA_FREE_OK"),
    VISA_FREE_EXCEEDED("VISA_FREE_EXCEEDED"),
    VISA_REQUIRED("VISA_REQUIRED"),
    UNVERIFIED("UNVERIFIED");

    private final String wireValue;

    VisaVerdict(String wireValue) {
        this.wireValue = wireValue;
    }

    public String wireValue() {
        return wireValue;
    }
}
```

- [ ] **Step 2: 판정 결과 레코드**

`server/src/main/java/com/travelfootsteps/visa/VisaJudgement.java`:

```java
package com.travelfootsteps.visa;

public record VisaJudgement(
        VisaVerdict verdict,
        int stayDays,
        Integer visaFreeDays,
        boolean passportOk,
        Integer passportValidityMonths,
        Integer passportShortfallDays
) {
}
```

- [ ] **Step 3: 실패하는 규칙 엔진 테스트 — 스펙 §6-①의 예시를 그대로 케이스로 옮긴다**

`server/src/test/java/com/travelfootsteps/visa/VisaJudgementServiceTest.java`:

```java
package com.travelfootsteps.visa;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class VisaJudgementServiceTest {

    private final VisaJudgementService service = new VisaJudgementService();

    private VisaRequirement requirement(boolean visaRequired, Integer visaFreeDays, Integer passportMonths) {
        VisaRequirement r = VisaRequirement.newUnverified(1L, "GENERAL");
        r.applyCollectedData(new ParsedVisaCondition(visaRequired, visaFreeDays, passportMonths),
                "raw", null, null, OffsetDateTime.now());
        return r;
    }

    @Test
    void 스펙_예시_베트남_20일_체류_45일_무비자_여권잔여85일_6개월요건_미달() {
        // 스펙 §6-① 예시: 2026-12-20 출발, 20일 체류, 여권만료 2027-03-15
        VisaRequirement req = requirement(false, 45, 6);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 3, 15));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_FREE_OK);
        assertThat(judgement.stayDays()).isEqualTo(20);
        assertThat(judgement.passportOk()).isFalse(); // 6개월(180일) 요건에 여권잔여 65일 미달
    }

    @Test
    void visa_free_days가_null이면_무조건_UNVERIFIED() {
        VisaRequirement req = requirement(false, null, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.UNVERIFIED);
    }

    @Test
    void visa_requirement_행_자체가_없으면_UNVERIFIED() {
        VisaJudgement judgement = service.judge(null,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.UNVERIFIED);
    }

    @Test
    void 무비자_체류일수_초과는_VISA_FREE_EXCEEDED() {
        VisaRequirement req = requirement(false, 15, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), // 20일 체류
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_FREE_EXCEEDED);
    }

    @Test
    void 비자_필요_국가는_VISA_REQUIRED이고_freeDays는_0() {
        VisaRequirement req = requirement(true, 0, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_REQUIRED);
    }

    @Test
    void 여권_요건이_null이면_요건없음으로_간주해_passportOk는_출국일_이후_유효만_확인한다() {
        VisaRequirement req = requirement(false, 90, null);

        VisaJudgement ok = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 1, 10)); // 귀국일 하루 뒤 만료 — 요건 없으니 OK

        assertThat(ok.passportOk()).isTrue();
        assertThat(ok.passportShortfallDays()).isNull();
    }

    @Test
    void 여권이_귀국일_이전에_만료되면_요건과_무관하게_실패한다() {
        VisaRequirement req = requirement(false, 90, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 1, 5)); // 귀국일보다 먼저 만료

        assertThat(judgement.passportOk()).isFalse();
        assertThat(judgement.passportShortfallDays()).isEqualTo(4);
    }
}
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*VisaJudgementServiceTest*'
```

기대: 컴파일 실패 — `VisaJudgementService` 심볼을 찾을 수 없음.

- [ ] **Step 5: 규칙 엔진 구현**

`server/src/main/java/com/travelfootsteps/visa/VisaJudgementService.java`:

```java
package com.travelfootsteps.visa;

import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

/**
 * 스펙 §6-①의 판정 로직을 그대로 구현한다. DB에 접근하지 않는 순수 도메인
 * 서비스다 — 어떤 VisaRequirement를 넘길지는 호출부(TripController)가 정한다.
 */
@Service
public class VisaJudgementService {

    public VisaJudgement judge(VisaRequirement requirement, LocalDate departDate,
                                LocalDate returnDate, LocalDate passportExpiry) {
        int stayDays = (int) ChronoUnit.DAYS.between(departDate, returnDate);

        Integer visaFreeDays = requirement != null ? requirement.getVisaFreeDays() : null;
        VisaVerdict verdict = determineVerdict(requirement, stayDays, visaFreeDays);

        Integer passportValidityMonths = requirement != null ? requirement.getPassportValidityMonths() : null;
        PassportCheck passportCheck = checkPassport(returnDate, passportExpiry, passportValidityMonths);

        return new VisaJudgement(verdict, stayDays, visaFreeDays,
                passportCheck.ok(), passportValidityMonths, passportCheck.shortfallDays());
    }

    private VisaVerdict determineVerdict(VisaRequirement requirement, int stayDays, Integer visaFreeDays) {
        if (requirement == null || visaFreeDays == null) {
            return VisaVerdict.UNVERIFIED;
        }
        if (!requirement.isVisaRequired() && stayDays <= visaFreeDays) {
            return VisaVerdict.VISA_FREE_OK;
        }
        if (!requirement.isVisaRequired()) {
            return VisaVerdict.VISA_FREE_EXCEEDED;
        }
        return VisaVerdict.VISA_REQUIRED;
    }

    private PassportCheck checkPassport(LocalDate returnDate, LocalDate passportExpiry, Integer requiredMonths) {
        if (passportExpiry.isBefore(returnDate)) {
            long shortfall = ChronoUnit.DAYS.between(passportExpiry, returnDate);
            return new PassportCheck(false, (int) shortfall);
        }
        if (requiredMonths == null) {
            return new PassportCheck(true, null);
        }
        LocalDate requiredMinExpiry = returnDate.plusMonths(requiredMonths);
        if (passportExpiry.isBefore(requiredMinExpiry)) {
            long shortfall = ChronoUnit.DAYS.between(passportExpiry, requiredMinExpiry);
            return new PassportCheck(false, (int) shortfall);
        }
        return new PassportCheck(true, null);
    }

    private record PassportCheck(boolean ok, Integer shortfallDays) {
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*VisaJudgementServiceTest*'
```

기대: 전체 PASS.

- [ ] **Step 7: 실패하는 역산 일정 생성기 테스트**

`server/src/test/java/com/travelfootsteps/trip/ScheduleGeneratorTest.java`:

```java
package com.travelfootsteps.trip;

import com.travelfootsteps.visa.VisaJudgement;
import com.travelfootsteps.visa.VisaVerdict;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;

class ScheduleGeneratorTest {

    private final ScheduleGenerator generator = new ScheduleGenerator();

    @Test
    void 여권_문제없고_무비자_가능이면_여권재발급과_비자신청_항목이_없다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.VISA_FREE_OK, 20, 45, true, 6, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title)
                .doesNotContain("여권 재발급", "비자 신청");
        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title)
                .contains("항공권·숙소 확정", "여행자보험 가입", "준비물 구매", "환전", "최종 서류 점검");
    }

    @Test
    void 여권_미달이면_D90에_여권_재발급_항목이_생긴다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.VISA_FREE_OK, 20, 45, false, 6, 65);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).anySatisfy(t -> {
            assertThat(t.title()).isEqualTo("여권 재발급");
            assertThat(t.dueDate()).isEqualTo(LocalDate.of(2026, 9, 21));
        });
    }

    @Test
    void 비자_필요_또는_초과면_D45에_비자_신청_항목이_생긴다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement required = new VisaJudgement(VisaVerdict.VISA_REQUIRED, 20, 0, true, null, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, required);

        assertThat(tasks).anySatisfy(t -> {
            assertThat(t.title()).isEqualTo("비자 신청");
            assertThat(t.dueDate()).isEqualTo(LocalDate.of(2026, 11, 5));
        });
    }

    @Test
    void 무비자_초과도_비자_신청_항목이_생긴다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement exceeded = new VisaJudgement(VisaVerdict.VISA_FREE_EXCEEDED, 30, 15, true, null, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, exceeded);

        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title).contains("비자 신청");
    }

    @Test
    void 공통_항목의_기준일은_출발일로부터_역산된다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.VISA_FREE_OK, 20, 45, true, null, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).anySatisfy(t -> {
            assertThat(t.title()).isEqualTo("최종 서류 점검");
            assertThat(t.dueDate()).isEqualTo(LocalDate.of(2026, 12, 13)); // D-7
        });
    }
}
```

> 위 테스트는 `import static org.assertj.core.api.Assertions.tuple;`을 쓰지 않으므로, 파일 상단 import 목록에도 넣지 않는다.

- [ ] **Step 8: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*ScheduleGeneratorTest*'
```

기대: 컴파일 실패 — `ScheduleGenerator` 심볼을 찾을 수 없음.

- [ ] **Step 9: 역산 일정 생성기 구현**

`server/src/main/java/com/travelfootsteps/trip/ScheduleGenerator.java`:

```java
package com.travelfootsteps.trip;

import com.travelfootsteps.visa.VisaJudgement;
import com.travelfootsteps.visa.VisaVerdict;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * 스펙 §6-①의 역산 일정을 만든다. departDate 기준으로 역산하며, 이미 지난
 * 날짜를 "지금 바로"로 표시하는 것은 앱(Plan B)의 화면 책임이다 — 여기서는
 * 실제 날짜만 계산한다.
 */
@Component
public class ScheduleGenerator {

    public record GeneratedTask(String title, LocalDate dueDate) {
    }

    public List<GeneratedTask> generate(LocalDate departDate, VisaJudgement judgement) {
        List<GeneratedTask> tasks = new ArrayList<>();

        if (!judgement.passportOk()) {
            tasks.add(new GeneratedTask("여권 재발급", departDate.minusDays(90)));
        }
        if (judgement.verdict() == VisaVerdict.VISA_REQUIRED
                || judgement.verdict() == VisaVerdict.VISA_FREE_EXCEEDED) {
            tasks.add(new GeneratedTask("비자 신청", departDate.minusDays(45)));
        }

        tasks.add(new GeneratedTask("항공권·숙소 확정", departDate.minusDays(30)));
        tasks.add(new GeneratedTask("여행자보험 가입", departDate.minusDays(30)));
        tasks.add(new GeneratedTask("준비물 구매", departDate.minusDays(14)));
        tasks.add(new GeneratedTask("환전", departDate.minusDays(14)));
        tasks.add(new GeneratedTask("최종 서류 점검", departDate.minusDays(7)));

        return tasks;
    }
}
```

- [ ] **Step 10: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*ScheduleGeneratorTest*'
```

기대: 전체 PASS.

- [ ] **Step 11: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/visa/VisaVerdict.java \
  server/src/main/java/com/travelfootsteps/visa/VisaJudgement.java \
  server/src/main/java/com/travelfootsteps/visa/VisaJudgementService.java \
  server/src/main/java/com/travelfootsteps/trip/ScheduleGenerator.java \
  server/src/test/java/com/travelfootsteps/visa/VisaJudgementServiceTest.java \
  server/src/test/java/com/travelfootsteps/trip/ScheduleGeneratorTest.java
git commit -m "feat(server): 비자 판정 규칙 엔진과 역산 일정 생성기"
```

---

### Task 6: 여행 계획 API — `POST/GET /api/trips`, 준비물 완료 처리

**Files:**
- Create: `server/src/main/resources/db/migration/V4__trip.sql`
- Create: `server/src/main/java/com/travelfootsteps/trip/Trip.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripTask.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripTaskRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/CreateTripRequest.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/VisaResultResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripTaskResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripNotFoundException.java`
- Create: `server/src/main/java/com/travelfootsteps/trip/TripController.java`
- Test: `server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java`

**Interfaces:**
- Consumes: Task 5의 `VisaJudgementService`/`ScheduleGenerator`, Task 3의 `VisaRequirementRepository`, Phase 0의 `CountryRepository`/인증
- Produces: `POST /api/trips`, `GET /api/trips/{id}`, `POST /api/trips/{id}/tasks/{taskId}/done`, **`POST /api/trips/{id}/refresh`(신규)** — Global Constraints 표의 JSON 계약 그대로. Plan B가 이 엔드포인트들을 그대로 소비한다. **`refresh`는 이 계획서 작성 이후 추가된 엔드포인트라 Plan B 문서에는 아직 반영되어 있지 않다 — Plan B 구현 시점에 Plan B 쪽에도 이 계약을 추가해야 한다.**

> **판정 스냅샷 고정 + 명시적 새로고침 (2026-09-12 리뷰 반영)**
>
> 기존 설계(조회 때마다 재계산)는 원본 데이터가 바뀌면 화면의 비자 판정과 이미 예약된 준비 일정·로컬 알람이 조용히 어긋나는 문제가 있었다. 대신 다음과 같이 고정한다.
>
> - `trip` 테이블에 스냅샷 컬럼을 추가한다: `verdict VARCHAR(30)`, `stay_days INTEGER`, `visa_free_days INTEGER`, `passport_ok BOOLEAN`, `passport_validity_months INTEGER`, `passport_shortfall_days INTEGER`, `requirement_updated_at TIMESTAMPTZ`(생성 시점에 사용한 `visa_requirement` 행의 최종 갱신 시각).
> - `POST /api/trips`는 `judge()`를 한 번만 호출해 그 결과를 위 컬럼에 그대로 저장하고, `scheduleGenerator.generate()`로 만든 `trip_task`도 그때 한 번만 만든다. 이후 조회에서는 재계산하지 않는다.
> - `GET /api/trips/{id}`는 저장된 스냅샷 컬럼을 그대로 `VisaResultResponse`에 담아 반환한다(라이브 `judge()` 호출 없음). 추가로, 그 국가의 현재 `visa_requirement.source_fetched_at`(또는 수기 검증 갱신 시각)을 스냅샷의 `requirement_updated_at`과 비교해 다르면 응답에 `judgementStale: true`를 포함한다. 앱(Plan B)은 이 플래그를 보고 "판정 기준이 바뀌었어요, 새로고침할까요?"를 사용자에게 물어본다.
> - **`POST /api/trips/{id}/refresh`(신규 엔드포인트)**: 사용자가 새로고침에 동의했을 때만 호출된다. `judge()`를 다시 계산해 스냅샷 컬럼을 덮어쓰고, 기존 `trip_task`를 전부 삭제한 뒤 새 일정으로 다시 생성한다(이미 완료 처리한 항목의 `done` 상태는 이 캡스톤 규모에서는 보존하지 않는다 — 새로고침하면 준비물 완료 체크가 초기화될 수 있음을 앱 쪽 확인 다이얼로그에 명시해야 한다). 응답 형식은 `GET`과 동일한 `TripResponse`.
> - 여행을 삭제하고 새로 만드는 경우는 항상 최신 규칙으로 판정된다(스냅샷이 새로 생성되므로 별도 처리 불필요).

- [ ] **Step 1: 마이그레이션**

`server/src/main/resources/db/migration/V4__trip.sql`:

```sql
CREATE TABLE trip (
    id               BIGSERIAL PRIMARY KEY,
    firebase_uid     VARCHAR(128) NOT NULL,
    country_id       BIGINT NOT NULL REFERENCES country(id),
    depart_date      DATE NOT NULL,
    return_date      DATE NOT NULL,
    passport_expiry  DATE NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT trip_date_check CHECK (return_date >= depart_date)
);

CREATE INDEX idx_trip_firebase_uid ON trip (firebase_uid);

CREATE TABLE trip_task (
    id              BIGSERIAL PRIMARY KEY,
    trip_id         BIGINT NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
    title           VARCHAR(100) NOT NULL,
    due_date        DATE NOT NULL,
    done            BOOLEAN NOT NULL DEFAULT false,
    notification_id INTEGER
);

CREATE INDEX idx_trip_task_trip ON trip_task (trip_id);
```

> `notification_id`는 스펙 §7에 정의되어 있지만, 이 계획의 API 계약(Global Constraints 표)에는 노출하지 않는다 — 로컬 알람 ID는 앱(Plan B)이 기기에서 스케줄링한 값이라 서버가 알 이유가 없다. 컬럼은 스펙과의 일관성을 위해 남겨 두되 이번 API에서는 쓰지 않는다.

- [ ] **Step 2: 엔티티**

`server/src/main/java/com/travelfootsteps/trip/Trip.java`:

```java
package com.travelfootsteps.trip;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.OffsetDateTime;

@Entity
@Table(name = "trip")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Trip {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "firebase_uid", nullable = false, length = 128)
    private String firebaseUid;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(name = "depart_date", nullable = false)
    private LocalDate departDate;

    @Column(name = "return_date", nullable = false)
    private LocalDate returnDate;

    @Column(name = "passport_expiry", nullable = false)
    private LocalDate passportExpiry;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    public static Trip create(String firebaseUid, Long countryId, LocalDate departDate,
                               LocalDate returnDate, LocalDate passportExpiry) {
        Trip trip = new Trip();
        trip.firebaseUid = firebaseUid;
        trip.countryId = countryId;
        trip.departDate = departDate;
        trip.returnDate = returnDate;
        trip.passportExpiry = passportExpiry;
        trip.createdAt = OffsetDateTime.now();
        return trip;
    }

    public boolean belongsTo(String firebaseUid) {
        return this.firebaseUid.equals(firebaseUid);
    }
}
```

`server/src/main/java/com/travelfootsteps/trip/TripTask.java`:

```java
package com.travelfootsteps.trip;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

@Entity
@Table(name = "trip_task")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TripTask {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "trip_id", nullable = false)
    private Long tripId;

    @Column(nullable = false, length = 100)
    private String title;

    @Column(name = "due_date", nullable = false)
    private LocalDate dueDate;

    @Column(nullable = false)
    private boolean done;

    public static TripTask create(Long tripId, String title, LocalDate dueDate) {
        TripTask task = new TripTask();
        task.tripId = tripId;
        task.title = title;
        task.dueDate = dueDate;
        task.done = false;
        return task;
    }

    public void markDone() {
        this.done = true;
    }
}
```

- [ ] **Step 3: 리포지토리**

`server/src/main/java/com/travelfootsteps/trip/TripRepository.java`:

```java
package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TripRepository extends JpaRepository<Trip, Long> {
}
```

`server/src/main/java/com/travelfootsteps/trip/TripTaskRepository.java`:

```java
package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface TripTaskRepository extends JpaRepository<TripTask, Long> {
    List<TripTask> findByTripIdOrderByDueDateAsc(Long tripId);
    Optional<TripTask> findByIdAndTripId(Long id, Long tripId);
}
```

- [ ] **Step 4: DTO — 응답 계약을 코드로 고정**

`server/src/main/java/com/travelfootsteps/trip/CreateTripRequest.java`:

```java
package com.travelfootsteps.trip;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;

public record CreateTripRequest(
        @NotBlank String countryIso2,
        @NotNull LocalDate departDate,
        @NotNull LocalDate returnDate,
        @NotNull LocalDate passportExpiry
) {
}
```

`server/src/main/java/com/travelfootsteps/trip/VisaResultResponse.java`:

```java
package com.travelfootsteps.trip;

import com.travelfootsteps.visa.VisaJudgement;

public record VisaResultResponse(
        String verdict,
        int stayDays,
        Integer visaFreeDays,
        boolean passportOk,
        Integer passportValidityMonths,
        Integer passportShortfallDays
) {
    public static VisaResultResponse from(VisaJudgement judgement) {
        return new VisaResultResponse(
                judgement.verdict().wireValue(),
                judgement.stayDays(),
                judgement.visaFreeDays(),
                judgement.passportOk(),
                judgement.passportValidityMonths(),
                judgement.passportShortfallDays()
        );
    }
}
```

`server/src/main/java/com/travelfootsteps/trip/TripTaskResponse.java`:

```java
package com.travelfootsteps.trip;

import java.time.LocalDate;

public record TripTaskResponse(Long id, String title, LocalDate dueDate, boolean done) {
    public static TripTaskResponse from(TripTask task) {
        return new TripTaskResponse(task.getId(), task.getTitle(), task.getDueDate(), task.isDone());
    }
}
```

`server/src/main/java/com/travelfootsteps/trip/TripResponse.java`:

```java
package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.visa.VisaJudgement;

import java.time.LocalDate;
import java.util.List;

public record TripResponse(
        Long id,
        String countryIso2,
        String countryNameKo,
        LocalDate departDate,
        LocalDate returnDate,
        LocalDate passportExpiry,
        VisaResultResponse visaResult,
        List<TripTaskResponse> tasks
) {
    public static TripResponse of(Trip trip, Country country, VisaJudgement judgement, List<TripTask> tasks) {
        return new TripResponse(
                trip.getId(),
                country.getIsoAlpha2(),
                country.getNameKo(),
                trip.getDepartDate(),
                trip.getReturnDate(),
                trip.getPassportExpiry(),
                VisaResultResponse.from(judgement),
                tasks.stream().map(TripTaskResponse::from).toList()
        );
    }
}
```

`server/src/main/java/com/travelfootsteps/trip/TripNotFoundException.java`:

```java
package com.travelfootsteps.trip;

public class TripNotFoundException extends RuntimeException {
    public TripNotFoundException(Long id) {
        super("여행 계획을 찾을 수 없습니다: " + id);
    }
}
```

- [ ] **Step 5: 실패하는 컨트롤러 테스트**

`server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java`:

```java
package com.travelfootsteps.trip;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.support.StubTokenVerifier;
import com.travelfootsteps.visa.ParsedVisaCondition;
import com.travelfootsteps.visa.VisaRequirement;
import com.travelfootsteps.visa.VisaRequirementRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(TripControllerTest.TestBeans.class)
class TripControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("token-a", "uid-a");
            stub.register("token-b", "uid-b");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;
    @Autowired CountryRepository countryRepository;
    @Autowired VisaRequirementRepository visaRequirementRepository;

    private void givenVietnamVisaFree45Days() {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        if (visaRequirementRepository.findByCountryIdAndPassportType(vietnam.getId(), "GENERAL").isPresent()) {
            return;
        }
        VisaRequirement req = VisaRequirement.newUnverified(vietnam.getId(), "GENERAL");
        req.applyCollectedData(new ParsedVisaCondition(false, 45, 6), "관광 목적 45일 무비자",
                null, null, OffsetDateTime.now());
        visaRequirementRepository.save(req);
    }

    @Test
    void 여행_생성시_비자_판정과_역산_일정을_함께_반환한다() throws Exception {
        givenVietnamVisaFree45Days();
        var request = new CreateTripRequest("VN",
                java.time.LocalDate.of(2026, 12, 20),
                java.time.LocalDate.of(2027, 1, 9),
                java.time.LocalDate.of(2027, 3, 15));

        mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.countryIso2").value("VN"))
                .andExpect(jsonPath("$.visaResult.verdict").value("VISA_FREE_OK"))
                .andExpect(jsonPath("$.visaResult.passportOk").value(false))
                .andExpect(jsonPath("$.tasks[?(@.title=='여권 재발급')]").exists())
                .andExpect(jsonPath("$.tasks[?(@.title=='비자 신청')]").doesNotExist());
    }

    @Test
    void 존재하지_않는_국가로_생성하면_404() throws Exception {
        var request = new CreateTripRequest("ZZ",
                java.time.LocalDate.of(2026, 12, 20),
                java.time.LocalDate.of(2027, 1, 9),
                java.time.LocalDate.of(2027, 3, 15));

        mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isNotFound());
    }

    @Test
    void 다른_사용자의_여행을_조회하면_404() throws Exception {
        givenVietnamVisaFree45Days();
        var request = new CreateTripRequest("VN",
                java.time.LocalDate.of(2026, 12, 20),
                java.time.LocalDate.of(2027, 1, 9),
                java.time.LocalDate.of(2028, 1, 1));

        String body = mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andReturn().getResponse().getContentAsString();
        Long tripId = objectMapper.readTree(body).get("id").asLong();

        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-b"))
                .andExpect(status().isNotFound());
    }

    @Test
    void 준비물_완료_처리하면_done이_true로_바뀐다() throws Exception {
        givenVietnamVisaFree45Days();
        var request = new CreateTripRequest("VN",
                java.time.LocalDate.of(2026, 12, 20),
                java.time.LocalDate.of(2027, 1, 9),
                java.time.LocalDate.of(2028, 1, 1));

        String body = mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andReturn().getResponse().getContentAsString();
        var tripJson = objectMapper.readTree(body);
        Long tripId = tripJson.get("id").asLong();
        Long taskId = tripJson.get("tasks").get(0).get("id").asLong();

        mockMvc.perform(post("/api/trips/" + tripId + "/tasks/" + taskId + "/done")
                        .header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.done").value(true));
    }
}
```

- [ ] **Step 6: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*TripControllerTest*'
```

기대: 컴파일 실패 — `TripController` 심볼을 찾을 수 없음.

- [ ] **Step 7: 컨트롤러 구현**

`server/src/main/java/com/travelfootsteps/trip/TripController.java`:

```java
package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.visa.VisaJudgement;
import com.travelfootsteps.visa.VisaJudgementService;
import com.travelfootsteps.visa.VisaRequirementRepository;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@RestController
@RequestMapping("/api/trips")
@RequiredArgsConstructor
public class TripController {

    private static final String PASSPORT_TYPE_GENERAL = "GENERAL";

    private final CountryRepository countryRepository;
    private final VisaRequirementRepository visaRequirementRepository;
    private final TripRepository tripRepository;
    private final TripTaskRepository tripTaskRepository;
    private final VisaJudgementService visaJudgementService;
    private final ScheduleGenerator scheduleGenerator;

    @PostMapping
    public TripResponse create(@Valid @RequestBody CreateTripRequest request, Authentication authentication) {
        Country country = findCountryOrThrow(request.countryIso2());
        VisaJudgement judgement = judge(country, request.departDate(), request.returnDate(),
                request.passportExpiry());

        Trip trip = tripRepository.save(Trip.create(authentication.getName(), country.getId(),
                request.departDate(), request.returnDate(), request.passportExpiry()));

        List<TripTask> tasks = scheduleGenerator.generate(request.departDate(), judgement).stream()
                .map(t -> tripTaskRepository.save(TripTask.create(trip.getId(), t.title(), t.dueDate())))
                .toList();

        return TripResponse.of(trip, country, judgement, tasks);
    }

    @GetMapping("/{id}")
    public TripResponse get(@PathVariable Long id, Authentication authentication) {
        Trip trip = findOwnedTripOrThrow(id, authentication.getName());
        Country country = countryRepository.findById(trip.getCountryId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가 데이터 손상"));
        VisaJudgement judgement = judge(country, trip.getDepartDate(), trip.getReturnDate(),
                trip.getPassportExpiry());
        List<TripTask> tasks = tripTaskRepository.findByTripIdOrderByDueDateAsc(trip.getId());

        return TripResponse.of(trip, country, judgement, tasks);
    }

    @PostMapping("/{id}/tasks/{taskId}/done")
    public TripTaskResponse markTaskDone(@PathVariable Long id, @PathVariable Long taskId,
                                          Authentication authentication) {
        findOwnedTripOrThrow(id, authentication.getName());
        TripTask task = tripTaskRepository.findByIdAndTripId(taskId, id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "준비물 항목을 찾을 수 없습니다"));
        task.markDone();
        tripTaskRepository.save(task);
        return TripTaskResponse.from(task);
    }

    private Trip findOwnedTripOrThrow(Long id, String uid) {
        Trip trip = tripRepository.findById(id).orElseThrow(() -> new TripNotFoundException(id));
        if (!trip.belongsTo(uid)) {
            // 소유자가 아니면 존재 여부 자체를 감춘다(404) — 403으로 존재를 알려주지 않는다.
            throw new TripNotFoundException(id);
        }
        return trip;
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
    }

    private VisaJudgement judge(Country country, java.time.LocalDate departDate,
                                 java.time.LocalDate returnDate, java.time.LocalDate passportExpiry) {
        var requirement = visaRequirementRepository
                .findByCountryIdAndPassportType(country.getId(), PASSPORT_TYPE_GENERAL)
                .orElse(null);
        return visaJudgementService.judge(requirement, departDate, returnDate, passportExpiry);
    }
}
```

`TripNotFoundException`을 404로 변환하려면 예외 핸들러가 필요하다. `server/src/main/java/com/travelfootsteps/trip/TripController.java`와 같은 패키지에 아래 클래스를 추가한다.

`server/src/main/java/com/travelfootsteps/trip/TripExceptionHandler.java`:

```java
package com.travelfootsteps.trip;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackageClasses = TripController.class)
public class TripExceptionHandler {

    @ExceptionHandler(TripNotFoundException.class)
    public ResponseEntity<Void> handleNotFound(TripNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
}
```

- [ ] **Step 8: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*TripControllerTest*'
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 9: 전체 회귀 테스트**

```bash
cd server && ./gradlew test
```

기대: 전체 PASS.

- [ ] **Step 10: 커밋**

```bash
git add server/src/main/resources/db/migration/V4__trip.sql \
  server/src/main/java/com/travelfootsteps/trip \
  server/src/test/java/com/travelfootsteps/trip/TripControllerTest.java
git commit -m "feat(server): 여행 계획 생성·조회·준비물 완료 API"
```

---

### Task 7: 국가 상세 정보와 준비물 체크리스트 템플릿

**Files:**
- Create: `server/src/main/resources/db/migration/V5__checklist_template.sql`
- Create: `server/src/main/java/com/travelfootsteps/country/CountryDetailResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/country/ChecklistTemplate.java`
- Create: `server/src/main/java/com/travelfootsteps/country/ChecklistTemplateRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/country/ChecklistTemplateResponse.java`
- Modify: `server/src/main/java/com/travelfootsteps/country/CountryController.java`
- Modify: `server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java`

**Interfaces:**
- Consumes: Phase 0의 `Country`/`CountryRepository`
- Produces: `GET /api/countries/{iso2}` → `CountryDetailResponse`(country 테이블 전체 컬럼 camelCase), `GET /api/countries/{iso2}/checklist` → `[ChecklistTemplateResponse]`(공통 템플릿 조회, `checked` 없음 — 기존 그대로), **`GET /api/trips/{tripId}/checklist`·`POST /api/trips/{tripId}/checklist/{itemId}/check`(신규, 아래 참고)**

> **체크·진행률 기능 추가 (2026-09-12 리뷰 반영)**
>
> 기존 계획은 국가 공통 템플릿 "조회"만 있고, 사용자가 체크하거나 진행률을 보는 기능이 빠져 있었다(스펙 §6-②의 필수 기능이 미완성 상태였다). 다음을 추가한다.
>
> - **신규 마이그레이션** `V8__trip_checklist.sql` (V7은 Task 11의 `footsteps`가 이미 사용): `trip_checklist(id, trip_id REFERENCES trip(id) ON DELETE CASCADE, category, title, description, priority, checked BOOLEAN NOT NULL DEFAULT false)`.
> - **Task 6(`POST /api/trips`) 수정**: 여행 생성 시 `checklist_template`에서 해당 국가 전용 + 공통(country_id IS NULL) 템플릿을 전부 복사해 그 여행의 `trip_checklist` 행을 만든다(스냅샷 — 이후 공통 템플릿이 바뀌어도 이미 만든 여행에는 영향 없음, Task 6의 판정 스냅샷과 같은 원칙).
> - `GET /api/trips/{tripId}/checklist` → `[{id, category, title, description, priority, checked}]`.
> - `POST /api/trips/{tripId}/checklist/{itemId}/check` — 요청 바디 `{checked: boolean}`, 응답은 갱신된 항목 하나. 소유자 검증은 Task 6의 `findOwnedTripOrThrow`와 동일한 패턴을 재사용한다.
> - **진행률은 별도 엔드포인트로 만들지 않는다** — 앱이 위 목록 응답의 `checked` 개수를 세어 계산한다(과설계 방지).
> - Plan B는 이 계획서 작성 이후 추가된 계약이라 아직 반영돼 있지 않다. Plan B 구현 시점에 체크 상태를 기기 로컬(`SharedPreferences`)이 아니라 이 API로 동기화하도록 갱신해야 한다.

- [ ] **Step 1: 마이그레이션 + 공통 템플릿 시드**

`server/src/main/resources/db/migration/V5__checklist_template.sql`:

```sql
CREATE TABLE checklist_template (
    id          BIGSERIAL PRIMARY KEY,
    country_id  BIGINT REFERENCES country(id),
    category    VARCHAR(30) NOT NULL,
    title       VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    priority    INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_checklist_template_country ON checklist_template (country_id);

-- country_id가 NULL인 행은 모든 국가에 공통으로 적용되는 템플릿이다.
INSERT INTO checklist_template (country_id, category, title, description, priority) VALUES
(NULL, 'POWER',     '플러그 어댑터 준비',       '목적지 플러그 타입에 맞는 어댑터를 준비한다', 10),
(NULL, 'POWER',     '보조배터리 용량 확인',      '항공 반입 규정(Wh 제한)을 확인한다', 20),
(NULL, 'PAYMENT',   '해외 결제 카드 준비',       '해외 결제 가능한 카드를 준비하거나 현금을 환전한다', 30),
(NULL, 'SIM',       '유심/eSIM 준비',           '현지 유심 또는 eSIM을 사전에 준비한다', 40),
(NULL, 'CLOTHING',  '계절 의류 확인',           '목적지 계절에 맞는 의류를 준비한다', 50),
(NULL, 'DOCUMENT',  '여행자보험 가입',          '여행 기간에 맞는 여행자보험에 가입한다', 60),
(NULL, 'DOCUMENT',  '왕복 항공권·숙소 확정',     '입국 심사 시 요구될 수 있다', 70),
(NULL, 'MONEY',     '환전',                    '목적지 통화로 환전한다', 80);
```

> 국가별 특화 항목(`country_id` 지정)은 이 계획서의 범위가 아니다 — R4가 Tier A 20개국 데이터 검증 작업(스펙 §8 R4 역할) 중 필요하면 같은 테이블에 `country_id`를 채운 행을 추가하면 된다. 스키마는 이미 그것을 지원한다.

- [ ] **Step 2: 엔티티/리포지토리/응답**

`server/src/main/java/com/travelfootsteps/country/ChecklistTemplate.java`:

```java
package com.travelfootsteps.country;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "checklist_template")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ChecklistTemplate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id")
    private Long countryId;

    @Column(nullable = false, length = 30)
    private String category;

    @Column(nullable = false, length = 100)
    private String title;

    @Column(length = 255)
    private String description;

    @Column(nullable = false)
    private int priority;
}
```

`server/src/main/java/com/travelfootsteps/country/ChecklistTemplateRepository.java`:

```java
package com.travelfootsteps.country;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ChecklistTemplateRepository extends JpaRepository<ChecklistTemplate, Long> {
    List<ChecklistTemplate> findByCountryIdIsNullOrCountryIdOrderByPriorityAsc(Long countryId);
}
```

`server/src/main/java/com/travelfootsteps/country/ChecklistTemplateResponse.java`:

```java
package com.travelfootsteps.country;

public record ChecklistTemplateResponse(Long id, String category, String title, String description, int priority) {
    public static ChecklistTemplateResponse from(ChecklistTemplate t) {
        return new ChecklistTemplateResponse(t.getId(), t.getCategory(), t.getTitle(), t.getDescription(), t.getPriority());
    }
}
```

`server/src/main/java/com/travelfootsteps/country/CountryDetailResponse.java`:

```java
package com.travelfootsteps.country;

public record CountryDetailResponse(
        String isoAlpha2, String isoAlpha3, String nameKo, String nameEn, String continent, String tier,
        String plugTypes, Integer voltageV, Integer frequencyHz, String currencyCode,
        String cardAcceptance, Integer powerBankWhLimit
) {
    public static CountryDetailResponse from(Country c) {
        return new CountryDetailResponse(
                c.getIsoAlpha2(), c.getIsoAlpha3(), c.getNameKo(), c.getNameEn(), c.getContinent(), c.getTier(),
                c.getPlugTypes(), c.getVoltageV(), c.getFrequencyHz(), c.getCurrencyCode(),
                c.getCardAcceptance(), c.getPowerBankWhLimit()
        );
    }
}
```

- [ ] **Step 3: 실패하는 테스트 추가 (기존 `CountryControllerTest`를 확장)**

`server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java`의 클래스 본문에 아래 테스트 메서드 3개를 추가한다 (Phase 0가 만든 기존 3개 테스트는 그대로 둔다).

```java
    @Test
    void 국가_상세_정보를_camelCase로_반환한다() throws Exception {
        mockMvc.perform(get("/api/countries/VN").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isoAlpha2").value("VN"))
                .andExpect(jsonPath("$.nameKo").value("베트남"))
                .andExpect(jsonPath("$.tier").value("A"));
    }

    @Test
    void 존재하지_않는_국가_상세는_404() throws Exception {
        mockMvc.perform(get("/api/countries/ZZ").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }

    @Test
    void 준비물_체크리스트는_공통_템플릿_8개를_우선순위순으로_반환한다() throws Exception {
        mockMvc.perform(get("/api/countries/VN/checklist").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(8))
                .andExpect(jsonPath("$[0].title").value("플러그 어댑터 준비"))
                .andExpect(jsonPath("$[0].category").value("POWER"));
    }
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*CountryControllerTest*'
```

기대: `국가_상세_정보를...`, `준비물_체크리스트는...` 실패 — `404 Not Found`(엔드포인트 없음).

- [ ] **Step 5: `CountryController` 확장**

`server/src/main/java/com/travelfootsteps/country/CountryController.java` 전체를 아래로 교체한다 (기존 `list()` 메서드를 유지하면서 두 메서드를 추가한다).

```java
package com.travelfootsteps.country;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@RestController
@RequestMapping("/api/countries")
@RequiredArgsConstructor
public class CountryController {

    private final CountryRepository countryRepository;
    private final ChecklistTemplateRepository checklistTemplateRepository;

    @GetMapping
    public List<CountryResponse> list() {
        return countryRepository.findAllByOrderByNameKoAsc()
                .stream()
                .map(CountryResponse::from)
                .toList();
    }

    @GetMapping("/{iso2}")
    public CountryDetailResponse detail(@PathVariable String iso2) {
        return CountryDetailResponse.from(findCountryOrThrow(iso2));
    }

    @GetMapping("/{iso2}/checklist")
    public List<ChecklistTemplateResponse> checklist(@PathVariable String iso2) {
        Country country = findCountryOrThrow(iso2);
        return checklistTemplateRepository
                .findByCountryIdIsNullOrCountryIdOrderByPriorityAsc(country.getId())
                .stream().map(ChecklistTemplateResponse::from).toList();
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*CountryControllerTest*'
```

기대: 6개 테스트 모두 PASS (Phase 0의 3개 + 이 태스크의 3개).

- [ ] **Step 7: 전체 회귀 테스트**

```bash
cd server && ./gradlew test
```

기대: 전체 PASS.

- [ ] **Step 8: 커밋**

```bash
git add server/src/main/resources/db/migration/V5__checklist_template.sql \
  server/src/main/java/com/travelfootsteps/country \
  server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java
git commit -m "feat(server): 국가 상세 정보와 준비물 체크리스트 템플릿 API"
```

---

### Task 8: 번역 프록시 + Places 프록시

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/translate/{TranslationClient,TranslationResult,GoogleTranslateClient,TranslateRequest,TranslateResponse,TranslateController}.java`
- Create: `server/src/main/java/com/travelfootsteps/places/{PlaceCategory,PlaceResult,PlacesClient,GooglePlacesClient,PlaceResponse,PlacesController}.java`
- Test: `server/src/test/java/com/travelfootsteps/translate/TranslateControllerTest.java`
- Test: `server/src/test/java/com/travelfootsteps/places/PlacesControllerTest.java`

**Interfaces:**
- Consumes: 없음 (독립적인 프록시). `google.server-api-key` 설정(Task 1에서 이미 `application.yml`에 추가됨)
- Produces:
  - `POST /api/translate` — 요청/응답은 Global Constraints 표(Plan E 계약)와 동일
  - `GET /api/places/nearby?lat&lng&radius&category` — 요청/응답은 Global Constraints 표(Plan F 계약)와 동일
  - `TranslationClient` 인터페이스 — 나중에 LLM 티어로 교체할 지점(스펙 §4, §12)

- [ ] **Step 1: 번역 — 인터페이스와 DTO**

`server/src/main/java/com/travelfootsteps/translate/TranslationResult.java`:

```java
package com.travelfootsteps.translate;

public record TranslationResult(String translatedText, String detectedSourceLanguage) {
}
```

`server/src/main/java/com/travelfootsteps/translate/TranslationClient.java` — 이 인터페이스 뒤에 NMT 구현체를 두고, 나중에 LLM 기반 구현체로 빈만 교체하면 컨트롤러는 변경되지 않는다.

```java
package com.travelfootsteps.translate;

public interface TranslationClient {
    TranslationResult translate(String text, String targetLanguage, String sourceLanguage);
}
```

`server/src/main/java/com/travelfootsteps/translate/TranslateRequest.java`:

```java
package com.travelfootsteps.translate;

import jakarta.validation.constraints.NotBlank;

public record TranslateRequest(@NotBlank String text, @NotBlank String targetLanguage, String sourceLanguage) {
}
```

`server/src/main/java/com/travelfootsteps/translate/TranslateResponse.java`:

```java
package com.travelfootsteps.translate;

public record TranslateResponse(String translatedText, String detectedSourceLanguage) {
    public static TranslateResponse from(TranslationResult result) {
        return new TranslateResponse(result.translatedText(), result.detectedSourceLanguage());
    }
}
```

- [ ] **Step 2: 실패하는 컨트롤러 테스트 (TranslationClient는 목으로 대체)**

`server/src/test/java/com/travelfootsteps/translate/TranslateControllerTest.java`:

```java
package com.travelfootsteps.translate;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TranslateControllerTest.TestBeans.class)
class TranslateControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        TranslationClient translationClient() {
            TranslationClient mock = mock(TranslationClient.class);
            when(mock.translate(eq("안녕하세요"), eq("en"), isNull()))
                    .thenReturn(new TranslationResult("Hello", "ko"));
            when(mock.translate(eq("안녕"), eq("fr"), eq("ko")))
                    .thenReturn(new TranslationResult("Bonjour", null));
            return mock;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;

    @Test
    void sourceLanguage_생략시_자동감지_결과를_포함해_반환한다() throws Exception {
        var request = new TranslateRequest("안녕하세요", "en", null);

        mockMvc.perform(post("/api/translate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.translatedText").value("Hello"))
                .andExpect(jsonPath("$.detectedSourceLanguage").value("ko"));
    }

    @Test
    void sourceLanguage_지정시_그대로_전달한다() throws Exception {
        var request = new TranslateRequest("안녕", "fr", "ko");

        mockMvc.perform(post("/api/translate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.translatedText").value("Bonjour"));
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        var request = new TranslateRequest("안녕", "en", null);

        mockMvc.perform(post("/api/translate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isUnauthorized());
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*TranslateControllerTest*'
```

기대: 컴파일 실패 — `TranslateController` 심볼을 찾을 수 없음.

- [ ] **Step 4: 컨트롤러와 실제 구현체 작성**

`server/src/main/java/com/travelfootsteps/translate/TranslateController.java`:

```java
package com.travelfootsteps.translate;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/translate")
@RequiredArgsConstructor
public class TranslateController {

    private final TranslationClient translationClient;

    @PostMapping
    public TranslateResponse translate(@Valid @RequestBody TranslateRequest request) {
        TranslationResult result = translationClient.translate(
                request.text(), request.targetLanguage(), request.sourceLanguage());
        return TranslateResponse.from(result);
    }
}
```

`server/src/main/java/com/travelfootsteps/translate/GoogleTranslateClient.java` — Google Cloud Translation v2 REST API. 실패 시 1회만 즉시 재시도하고, 그래도 실패하면 502로 전파한다(Global Constraints의 사용자 요청 경로 정책).

```java
package com.travelfootsteps.translate;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@Component
@Profile("!test")
public class GoogleTranslateClient implements TranslationClient {

    private final RestClient restClient;
    private final String apiKey;

    public GoogleTranslateClient(RestClient.Builder builder, @Value("${google.server-api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://translation.googleapis.com").build();
        this.apiKey = apiKey;
    }

    @Override
    public TranslationResult translate(String text, String targetLanguage, String sourceLanguage) {
        try {
            return callOnce(text, targetLanguage, sourceLanguage);
        } catch (Exception firstFailure) {
            try {
                return callOnce(text, targetLanguage, sourceLanguage);
            } catch (Exception secondFailure) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "번역 서비스 호출 실패", secondFailure);
            }
        }
    }

    private TranslationResult callOnce(String text, String targetLanguage, String sourceLanguage) {
        Map<String, Object> body = sourceLanguage == null
                ? Map.of("q", text, "target", targetLanguage, "format", "text")
                : Map.of("q", text, "target", targetLanguage, "source", sourceLanguage, "format", "text");

        JsonNode response = restClient.post()
                .uri(uriBuilder -> uriBuilder.path("/language/translate/v2").queryParam("key", apiKey).build())
                .body(body)
                .retrieve()
                .body(JsonNode.class);

        JsonNode translation = response.path("data").path("translations").get(0);
        String translatedText = translation.path("translatedText").asText();
        String detected = sourceLanguage == null && translation.hasNonNull("detectedSourceLanguage")
                ? translation.path("detectedSourceLanguage").asText() : null;

        return new TranslationResult(translatedText, detected);
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*TranslateControllerTest*'
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 6: Places — 카테고리·클라이언트·DTO**

`server/src/main/java/com/travelfootsteps/places/PlaceCategory.java`:

```java
package com.travelfootsteps.places;

public enum PlaceCategory {
    TOURIST("tourist_attraction"),
    RESTAURANT("restaurant"),
    PHARMACY("pharmacy"),
    ATM("atm");

    private final String googlePlaceType;

    PlaceCategory(String googlePlaceType) {
        this.googlePlaceType = googlePlaceType;
    }

    public String googlePlaceType() {
        return googlePlaceType;
    }
}
```

`server/src/main/java/com/travelfootsteps/places/PlaceResult.java`:

```java
package com.travelfootsteps.places;

public record PlaceResult(String id, String name, PlaceCategory category, String address, double lat, double lng) {
}
```

`server/src/main/java/com/travelfootsteps/places/PlaceResponse.java`:

```java
package com.travelfootsteps.places;

public record PlaceResponse(String id, String name, String category, String address, double lat, double lng) {
    public static PlaceResponse from(PlaceResult r) {
        return new PlaceResponse(r.id(), r.name(), r.category().name(), r.address(), r.lat(), r.lng());
    }
}
```

`server/src/main/java/com/travelfootsteps/places/PlacesClient.java`:

```java
package com.travelfootsteps.places;

import java.util.List;

public interface PlacesClient {
    List<PlaceResult> nearby(double lat, double lng, int radiusMeters, PlaceCategory category);
}
```

`server/src/main/java/com/travelfootsteps/places/GooglePlacesClient.java`:

```java
package com.travelfootsteps.places;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;

@Component
@Profile("!test")
public class GooglePlacesClient implements PlacesClient {

    private final RestClient restClient;
    private final String apiKey;

    public GooglePlacesClient(RestClient.Builder builder, @Value("${google.server-api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://maps.googleapis.com").build();
        this.apiKey = apiKey;
    }

    @Override
    public List<PlaceResult> nearby(double lat, double lng, int radiusMeters, PlaceCategory category) {
        try {
            return callOnce(lat, lng, radiusMeters, category);
        } catch (Exception firstFailure) {
            try {
                return callOnce(lat, lng, radiusMeters, category);
            } catch (Exception secondFailure) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "주변정보 서비스 호출 실패", secondFailure);
            }
        }
    }

    private List<PlaceResult> callOnce(double lat, double lng, int radiusMeters, PlaceCategory category) {
        JsonNode response = restClient.get()
                .uri(uriBuilder -> uriBuilder.path("/maps/api/place/nearbysearch/json")
                        .queryParam("location", lat + "," + lng)
                        .queryParam("radius", radiusMeters)
                        .queryParam("type", category.googlePlaceType())
                        .queryParam("key", apiKey)
                        .build())
                .retrieve()
                .body(JsonNode.class);

        List<PlaceResult> results = new ArrayList<>();
        for (JsonNode item : response.path("results")) {
            results.add(new PlaceResult(
                    item.path("place_id").asText(),
                    item.path("name").asText(),
                    category,
                    item.path("vicinity").asText(null),
                    item.path("geometry").path("location").path("lat").asDouble(),
                    item.path("geometry").path("location").path("lng").asDouble()
            ));
        }
        return results;
    }
}
```

`server/src/main/java/com/travelfootsteps/places/PlacesController.java`:

```java
package com.travelfootsteps.places;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/places")
@RequiredArgsConstructor
public class PlacesController {

    private final PlacesClient placesClient;

    @GetMapping("/nearby")
    public List<PlaceResponse> nearby(@RequestParam double lat, @RequestParam double lng,
                                       @RequestParam(defaultValue = "1000") int radius,
                                       @RequestParam PlaceCategory category) {
        return placesClient.nearby(lat, lng, radius, category)
                .stream().map(PlaceResponse::from).toList();
    }
}
```

- [ ] **Step 7: 실패하는 Places 컨트롤러 테스트**

`server/src/test/java/com/travelfootsteps/places/PlacesControllerTest.java`:

```java
package com.travelfootsteps.places;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(PlacesControllerTest.TestBeans.class)
class PlacesControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        PlacesClient placesClient() {
            PlacesClient mock = mock(PlacesClient.class);
            when(mock.nearby(eq(37.5), eq(127.0), eq(500), eq(PlaceCategory.RESTAURANT)))
                    .thenReturn(List.of(new PlaceResult("p1", "테스트 식당", PlaceCategory.RESTAURANT,
                            "서울", 37.5, 127.0)));
            return mock;
        }
    }

    @Autowired MockMvc mockMvc;

    @Test
    void 카테고리로_주변정보를_조회한다() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .header("Authorization", "Bearer valid-token")
                        .param("lat", "37.5").param("lng", "127.0")
                        .param("radius", "500").param("category", "RESTAURANT"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("테스트 식당"))
                .andExpect(jsonPath("$[0].category").value("RESTAURANT"));
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.5").param("lng", "127.0").param("category", "RESTAURANT"))
                .andExpect(status().isUnauthorized());
    }
}
```

- [ ] **Step 8: 테스트 실패 확인 후 구현 확인**

```bash
cd server && ./gradlew test --tests '*PlacesControllerTest*'
```

기대: Step 6에서 이미 구현을 작성했으므로 바로 PASS해야 한다(2개). 만약 컴파일 실패가 난다면 Step 6의 파일 중 누락된 것이 없는지 확인한다.

- [ ] **Step 9: 전체 회귀 테스트**

```bash
cd server && ./gradlew test
```

기대: 전체 PASS.

- [ ] **Step 10: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/translate \
  server/src/main/java/com/travelfootsteps/places \
  server/src/test/java/com/travelfootsteps/translate \
  server/src/test/java/com/travelfootsteps/places
git commit -m "feat(server): 번역 프록시와 Places 프록시"
```

---

### Task 9: 환율 캐시 (T3 — 여유 없으면 자를 수 있음)

> **우선순위 경고**: 스펙 §6/§10에 따라 이 기능은 필수 6개 기능 밖의 확장(T3)이며, "여유가 없어질 때 자르는 순서"의 1번이다. 일정이 밀리면 이 태스크 전체를, 또는 최소한 아래 "Step 9~10(환전 알림)"만 생략할 수 있다. Step 1~8(환율 캐시 배치 + 조회 API)까지만 완료해도 Plan B의 환율 표시 기능은 정상 동작한다.

**Files:**
- Create: `server/src/main/resources/db/migration/V6__exchange_rate.sql`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRate.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximApiItem.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximClient.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateController.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeAlertScheduler.java` (Step 9~10, 생략 가능)
- Test: `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateControllerTest.java`
- Test: `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateBatchSchedulerTest.java`

**Interfaces:**
- Consumes: 없음 (독립 기능). `.env`의 `KOREA_EXIM_API_KEY` (Task 1에서 `application.yml`에 이미 바인딩됨)
- Produces: `GET /api/exchange-rates/{currencyCode}` → `{currencyCode, krwRate, baseDate}` (Global Constraints 표, Plan B 계약)

- [ ] **Step 1: 마이그레이션**

`server/src/main/resources/db/migration/V6__exchange_rate.sql`:

```sql
CREATE TABLE exchange_rate (
    id            BIGSERIAL PRIMARY KEY,
    currency_code CHAR(3) NOT NULL UNIQUE,
    krw_rate      NUMERIC(12, 4) NOT NULL,
    base_date     DATE NOT NULL
);
```

- [ ] **Step 2: 엔티티/리포지토리/API 클라이언트**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRate.java`:

```java
package com.travelfootsteps.exchangerate;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;

@Entity
@Table(name = "exchange_rate")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ExchangeRate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "currency_code", nullable = false, unique = true, length = 3)
    private String currencyCode;

    @Column(name = "krw_rate", nullable = false, precision = 12, scale = 4)
    private BigDecimal krwRate;

    @Column(name = "base_date", nullable = false)
    private LocalDate baseDate;

    public static ExchangeRate of(String currencyCode, BigDecimal krwRate, LocalDate baseDate) {
        ExchangeRate rate = new ExchangeRate();
        rate.currencyCode = currencyCode;
        rate.krwRate = krwRate;
        rate.baseDate = baseDate;
        return rate;
    }

    public void update(BigDecimal krwRate, LocalDate baseDate) {
        this.krwRate = krwRate;
        this.baseDate = baseDate;
    }
}
```

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateRepository.java`:

```java
package com.travelfootsteps.exchangerate;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ExchangeRateRepository extends JpaRepository<ExchangeRate, Long> {
    Optional<ExchangeRate> findByCurrencyCode(String currencyCode);
}
```

`server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximApiItem.java` — 한국수출입은행 API는 통화 단위가 100 단위로 고시되는 통화(JPY, IDR 등)를 `cur_unit`에 `"JPY(100)"`처럼 표기한다.

```java
package com.travelfootsteps.exchangerate;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record KoreaEximApiItem(
        @JsonProperty("result") int result,
        @JsonProperty("cur_unit") String currencyUnit,
        @JsonProperty("deal_bas_r") String dealBaseRate
) {
    public String normalizedCurrencyCode() {
        int parenIndex = currencyUnit.indexOf('(');
        return parenIndex > 0 ? currencyUnit.substring(0, parenIndex) : currencyUnit;
    }

    public boolean isPerHundredUnits() {
        return currencyUnit.contains("(100)");
    }
}
```

`server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximClient.java`:

```java
package com.travelfootsteps.exchangerate;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

@Component
public class KoreaEximClient {

    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final RestClient restClient;
    private final String apiKey;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public KoreaEximClient(RestClient.Builder builder, @Value("${korea-exim.api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://oapi.koreaexim.go.kr").build();
        this.apiKey = apiKey;
    }

    public List<KoreaEximApiItem> fetchTodayRates() {
        return fetchRates(LocalDate.now());
    }

    public List<KoreaEximApiItem> fetchRates(LocalDate date) {
        String body = restClient.get()
                .uri(uriBuilder -> uriBuilder.path("/site/program/financial/exchangeJSON")
                        .queryParam("authkey", apiKey)
                        .queryParam("searchdate", date.format(DATE_FORMAT))
                        .queryParam("data", "AP01")
                        .build())
                .retrieve()
                .body(String.class);
        try {
            return List.of(objectMapper.readValue(body, KoreaEximApiItem[].class));
        } catch (Exception e) {
            throw new com.travelfootsteps.externaldata.ExternalApiException("한국수출입은행 환율 응답 파싱 실패", e);
        }
    }
}
```

> **영업일 주의**: 한국수출입은행 API는 주말·공휴일에는 최신 영업일 데이터를 반환하거나 빈 배열을 반환할 수 있다. `result != 1`인 항목은 무시하고, 빈 배열이면 배치가 그냥 아무 것도 갱신하지 않고 종료한다 — 이전 캐시 값이 계속 유효한 것으로 취급한다(Global Constraints의 degrade 정책과 동일한 원칙).

- [ ] **Step 3: 배치 스케줄러**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java`:

```java
package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;

@Slf4j
@Component
@RequiredArgsConstructor
public class ExchangeRateBatchScheduler {

    private final KoreaEximClient client;
    private final ExchangeRateRepository repository;

    /** 매일 07:00(KST) — 한국수출입은행이 영업일 고시환율을 발표한 이후 시각. */
    @Scheduled(cron = "0 0 7 * * *", zone = "Asia/Seoul")
    @Transactional
    public void runDaily() {
        try {
            var items = client.fetchTodayRates();
            LocalDate today = LocalDate.now();
            int updated = 0;
            for (KoreaEximApiItem item : items) {
                if (item.result() != 1) {
                    continue;
                }
                BigDecimal rate = parseRate(item.dealBaseRate());
                if (item.isPerHundredUnits()) {
                    rate = rate.divide(BigDecimal.valueOf(100));
                }
                upsert(item.normalizedCurrencyCode(), rate, today);
                updated++;
            }
            log.info("환율 배치 완료: {}건 갱신", updated);
        } catch (Exception e) {
            log.error("환율 배치 실패 — 기존 캐시를 유지한다", e);
        }
    }

    private void upsert(String currencyCode, BigDecimal rate, LocalDate baseDate) {
        repository.findByCurrencyCode(currencyCode)
                .ifPresentOrElse(
                        existing -> existing.update(rate, baseDate),
                        () -> repository.save(ExchangeRate.of(currencyCode, rate, baseDate))
                );
    }

    private BigDecimal parseRate(String raw) {
        return new BigDecimal(raw.replace(",", ""));
    }
}
```

- [ ] **Step 4: 실패하는 배치 테스트**

`server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateBatchSchedulerTest.java`:

```java
package com.travelfootsteps.exchangerate;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ExchangeRateBatchSchedulerTest {

    @Mock KoreaEximClient client;
    @Mock ExchangeRateRepository repository;

    @Test
    void 콤마_포함_숫자와_100단위_통화를_정규화해서_저장한다() {
        when(client.fetchTodayRates()).thenReturn(List.of(
                new KoreaEximApiItem(1, "USD", "1,320.50"),
                new KoreaEximApiItem(1, "JPY(100)", "895.30")
        ));
        when(repository.findByCurrencyCode(any())).thenReturn(Optional.empty());

        new ExchangeRateBatchScheduler(client, repository).runDaily();

        verify(repository).save(argThat(r -> r.getCurrencyCode().equals("USD")
                && r.getKrwRate().compareTo(new BigDecimal("1320.50")) == 0));
        verify(repository).save(argThat(r -> r.getCurrencyCode().equals("JPY")
                && r.getKrwRate().compareTo(new BigDecimal("8.9530")) == 0));
    }

    @Test
    void result가_1이_아닌_항목은_건너뛴다() {
        when(client.fetchTodayRates()).thenReturn(List.of(new KoreaEximApiItem(2, "USD", "1,320.50")));

        new ExchangeRateBatchScheduler(client, repository).runDaily();

        verify(repository, never()).save(any());
    }

    @Test
    void API_호출이_실패해도_예외를_던지지_않는다() {
        when(client.fetchTodayRates())
                .thenThrow(new com.travelfootsteps.externaldata.ExternalApiException("장애"));

        new ExchangeRateBatchScheduler(client, repository).runDaily(); // 예외 없이 반환
    }
}
```

- [ ] **Step 5: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*ExchangeRateBatchSchedulerTest*'
```

기대: 컴파일 실패 — Step 2, 3에서 이미 클래스를 작성했다면 바로 통과해야 한다. 순서를 지켜 Step 3 이전에 이 커맨드를 먼저 실행했다면 컴파일 실패를 확인할 수 있다.

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*ExchangeRateBatchSchedulerTest*'
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 7: 조회 API**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateResponse.java`:

```java
package com.travelfootsteps.exchangerate;

import java.math.BigDecimal;
import java.time.LocalDate;

public record ExchangeRateResponse(String currencyCode, BigDecimal krwRate, LocalDate baseDate) {
    public static ExchangeRateResponse from(ExchangeRate rate) {
        return new ExchangeRateResponse(rate.getCurrencyCode(), rate.getKrwRate(), rate.getBaseDate());
    }
}
```

`server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateControllerTest.java`:

```java
package com.travelfootsteps.exchangerate;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(ExchangeRateControllerTest.TestBeans.class)
class ExchangeRateControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ExchangeRateRepository repository;

    @Test
    void 캐시된_환율을_반환한다() throws Exception {
        repository.save(ExchangeRate.of("VND", new BigDecimal("0.0540"), LocalDate.of(2026, 9, 7)));

        mockMvc.perform(get("/api/exchange-rates/VND").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currencyCode").value("VND"))
                .andExpect(jsonPath("$.krwRate").value(0.0540));
    }

    @Test
    void 캐시에_없는_통화는_404() throws Exception {
        mockMvc.perform(get("/api/exchange-rates/XXX").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }
}
```

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateController.java`:

```java
package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/exchange-rates")
@RequiredArgsConstructor
public class ExchangeRateController {

    private final ExchangeRateRepository repository;

    @GetMapping("/{currencyCode}")
    public ExchangeRateResponse get(@PathVariable String currencyCode) {
        return repository.findByCurrencyCode(currencyCode.toUpperCase())
                .map(ExchangeRateResponse::from)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "캐시된 환율이 없습니다: " + currencyCode));
    }
}
```

- [ ] **Step 8: 테스트 통과 확인 + 전체 회귀 테스트**

```bash
cd server && ./gradlew test --tests '*ExchangeRateControllerTest*'
cd server && ./gradlew test
```

기대: 둘 다 전체 PASS. **여기까지 완료하면 환율 캐시의 핵심 기능(T3 안에서도 최우선순위)이 끝난다. 시간이 부족하면 아래 Step 9~10은 생략하고 바로 Step 11(커밋)로 간다.**

- [ ] **Step 9 (생략 가능): FCM 환전 알림 — Firestore에서 FCM 토큰 조회**

스펙 §6-⑦: "미체크 && D-14 이내면 매일 오전 1회 FCM 푸시". `trip_task.title = '환전'`이고 `done = false`이며 `due_date`가 오늘부터 14일 이내인 행을 찾아, 해당 여행의 `firebase_uid`로 Firestore `users/{uid}.fcmToken`을 조회해 푸시를 보낸다. Firebase Admin SDK는 Phase 0 Task 5가 이미 초기화했다.

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeAlertScheduler.java`:

```java
package com.travelfootsteps.exchangerate;

import com.google.cloud.firestore.Firestore;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.travelfootsteps.trip.TripRepository;
import com.travelfootsteps.trip.TripTaskRepository;
import jakarta.persistence.EntityManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * 여유 없으면 생략 가능한 T3 서브기능. trip_task 중 "환전" 항목이 미완료이고
 * D-14 이내인 여행을 매일 찾아 FCM 푸시를 보낸다. FCM 토큰은 Postgres가 아니라
 * Firestore users/{uid}.fcmToken에 있다(스펙 §7 Firestore 데이터 모델) — 서버가
 * Firebase Admin SDK로 직접 조회한다.
 */
@Slf4j
@Component
@Profile("!test")
@RequiredArgsConstructor
public class ExchangeAlertScheduler {

    private static final int REMINDER_WINDOW_DAYS = 14;

    private final EntityManager entityManager;
    private final ExchangeRateRepository exchangeRateRepository;
    private final Firestore firestore;
    private final FirebaseMessaging firebaseMessaging;

    @Scheduled(cron = "0 0 9 * * *", zone = "Asia/Seoul")
    public void runDaily() {
        LocalDate today = LocalDate.now();
        LocalDate windowEnd = today.plusDays(REMINDER_WINDOW_DAYS);

        List<Object[]> rows = entityManager.createNativeQuery(
                        "SELECT t.firebase_uid, c.currency_code, c.name_ko " +
                        "FROM trip_task tt " +
                        "JOIN trip t ON t.id = tt.trip_id " +
                        "JOIN country c ON c.id = t.country_id " +
                        "WHERE tt.title = '환전' AND tt.done = false " +
                        "AND tt.due_date BETWEEN :today AND :windowEnd")
                .setParameter("today", today)
                .setParameter("windowEnd", windowEnd)
                .getResultList();

        for (Object[] row : rows) {
            sendReminder((String) row[0], (String) row[1], (String) row[2]);
        }
    }

    private void sendReminder(String firebaseUid, String currencyCode, String countryNameKo) {
        try {
            String fcmToken = lookupFcmToken(firebaseUid);
            if (fcmToken == null) {
                return;
            }
            var rate = exchangeRateRepository.findByCurrencyCode(currencyCode).orElse(null);
            if (rate == null) {
                return;
            }
            String body = "오늘 " + countryNameKo + " 환율 " + rate.getKrwRate() + "원";
            Message message = Message.builder()
                    .setToken(fcmToken)
                    .putData("type", "EXCHANGE_REMINDER")
                    .putData("body", body)
                    .build();
            firebaseMessaging.send(message);
        } catch (Exception e) {
            log.warn("환전 알림 발송 실패: uid={}, reason={}", firebaseUid, e.getMessage());
        }
    }

    private String lookupFcmToken(String uid) throws Exception {
        var snapshot = firestore.collection("users").document(uid).get().get();
        if (!snapshot.exists()) {
            return null;
        }
        return snapshot.getString("fcmToken");
    }
}
```

- [ ] **Step 10 (생략 가능): 수동 검증**

이 서브기능은 실제 여행/Firestore 사용자 데이터가 있어야 눈으로 확인할 수 있어 자동 테스트보다 수동 시나리오로 검증한다. `@Profile("!test")`이므로 단위 테스트 스위트에는 포함하지 않는다(레포지토리 쿼리 자체는 Task 6의 `TripControllerTest`가 만든 `trip_task` 스키마와 호환되는지 SQL 문법만 리뷰한다).

```bash
# 로컬에서 실기기 없이 확인하려면: 테스트 여행 하나를 만들고 trip_task.title='환전'인 행의
# due_date를 오늘+7일로 UPDATE한 뒤, ExchangeAlertScheduler.runDaily()를 REST 컨트롤러
# 없이 임시로 노출하거나 IDE에서 직접 호출해 로그를 확인한다.
```

- [ ] **Step 11: 커밋**

```bash
git add server/src/main/resources/db/migration/V6__exchange_rate.sql \
  server/src/main/java/com/travelfootsteps/exchangerate \
  server/src/test/java/com/travelfootsteps/exchangerate
git commit -m "feat(server): 환율 캐시 배치·조회 API (T3)"
```

Step 9~10(FCM 알림)을 생략했다면 커밋 메시지에 `(환전 알림 제외)`를 덧붙인다.

---

### Task 10: WebSocket(STOMP) 위치 릴레이 — 그룹 실시간 위치공유 서버측

> **통합 공백 메모**: 이 태스크는 최초 계획 작성 시 "Plan D(R2)가 만들 것"이라 가정하고 범위에서 뺐던 기능이다. 스펙 §8 역할분담 표는 이 서버 릴레이를 R1(백엔드) 책임으로 명시하고, Plan D는 반대로 "Plan A가 이미 만들어 뒀다"고 가정하고 Flutter STOMP 클라이언트만 작성했다(`docs/superpowers/plans/2026-09-07-plan-d-chat-location-sharing.md` Task 8). 두 계획서가 서로 미뤄서 비었던 부분을 이 Task로 메운다.

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/location/WebSocketConfig.java`
- Create: `server/src/main/java/com/travelfootsteps/location/StompAuthChannelInterceptor.java`
- Create: `server/src/main/java/com/travelfootsteps/location/StompAuthenticationException.java`
- Create: `server/src/main/java/com/travelfootsteps/location/LocationMessage.java`
- Create: `server/src/main/java/com/travelfootsteps/location/LocationBroadcast.java`
- Create: `server/src/main/java/com/travelfootsteps/location/LocationRelayController.java`
- Test: `server/src/test/java/com/travelfootsteps/location/LocationRelayControllerTest.java`
- Test: `server/src/test/java/com/travelfootsteps/location/StompAuthChannelInterceptorTest.java`
- Modify: `server/build.gradle`

**Interfaces:**
- Consumes: Phase 0 Task 5의 `TokenVerifier`(HTTP `FirebaseAuthFilter`는 STOMP 핸드셰이크 자체에는 적용되지만 개별 STOMP 프레임 인증은 별도로 처리해야 한다 — 아래 설계 참고), 스펙 §7의 STOMP 계약, Plan D(`2026-09-07-plan-d-chat-location-sharing.md` 2264·2469줄)가 이미 클라이언트에서 가정한 브로드캐스트 페이로드 `{uid, lat, lng, ts}`.
- Produces:
  - `WS /ws` (SockJS 미사용, 순수 STOMP-over-WebSocket 엔드포인트)
  - `SEND /app/location` — 요청 바디 `{roomId, lat, lng, ts}` (Plan D가 실제로 보내는 필드 그대로, `ts`는 클라이언트 로컬시각 epoch millis)
  - `SUBSCRIBE /topic/group/{roomId}/location` — 브로드캐스트 바디 `{uid, lat, lng, ts}`. `uid`는 발신자의 STOMP 세션 Principal에서 서버가 채워 넣는다(클라이언트가 uid를 자기 신고로 보내지 않는다 — 위조 방지).
  - **저장하지 않는다.** DB 테이블 없음, 메모리 릴레이만 (스펙 §3, §6-④).

> **왜 HTTP 인증 필터로는 부족한가**: Phase 0의 `FirebaseAuthFilter`(`OncePerRequestFilter`)는 서블릿 필터 체인에서 동작하므로 `/ws`로 들어오는 최초 HTTP Upgrade 요청 자체에는 적용된다. 하지만 그 이후 하나의 WebSocket 연결 위에서 여러 STOMP 프레임(CONNECT, SUBSCRIBE, SEND, ...)이 다중화되어 오가는데, 서블릿 필터는 이 프레임들을 보지 못한다. 따라서 실제 사용자 인증(uid 확보)은 STOMP `ChannelInterceptor`가 CONNECT 프레임의 `Authorization` 네이티브 헤더에서 토큰을 꺼내 `TokenVerifier`로 검증하고, 세션의 Principal로 고정하는 방식으로 별도 구현한다. 이후 같은 세션에서 오는 SEND/SUBSCRIBE 프레임은 이 Principal을 그대로 물려받는다(Spring 표준 STOMP 세션 인증 패턴).

> **그룹 멤버십 인가 — v1 범위 판단 (2026-09-12 리뷰 후 재확정)**: 스펙상 그룹 실시간 위치공유는 `rooms/{roomId}.participants[]`(Firestore, Plan D 소유)로 멤버를 판별한다. 서버가 이걸 확인하려면 Firebase Admin SDK로 매 SEND/SUBSCRIBE마다 Firestore를 읽어야 하는데, 이는 캡스톤 범위에서 추가 인프라(서버가 Firestore 클라이언트를 갖는 것 자체는 Task 9에서 이미 함)와 매 프레임마다의 왕복 지연을 더한다. **이 Task는 그룹 멤버십 검증을 생략한다** — 대신 (1) STOMP 세션 자체는 유효한 Firebase 사용자만 맺을 수 있고(익명 접속 불가), (2) `roomId`는 초대 코드로만 얻을 수 있는 비공개 식별자이므로, "로그인한 사용자이면서 roomId를 아는 사람만 접근 가능"이라는 최소 보장으로 v1은 충분하다고 판단했다.
>
> **이 판단은 전제 조건이 있다**: (2)가 성립하려면 `roomId`가 실제로 초대 코드를 거치지 않고는 알아낼 수 없는 값이어야 한다. 그런데 Plan D의 Firestore 규칙(`inviteCodes` 컬렉션)이 `list` 쿼리를 막지 않고 있어, 로그인한 아무 사용자나 전체 초대 코드→roomId 매핑을 긁어올 수 있는 별도 버그가 있다(Plan D 소유, 이 계획서 범위 밖이지만 **이 버그가 고쳐지지 않으면 위 (2)의 전제가 깨져서 이 Task의 인가 생략 판단 전체가 무효화된다** — Plan D 구현 시 `inviteCodes`에 `allow get`만 허용하고 `allow list`는 반드시 막아야 한다).
> - **남는 잔여 리스크(수용함)**: 한 번 그룹에 참여했다가 나간 사용자도 `roomId`를 계속 기억하고 있으면 멤버십 재확인이 없어 위치를 계속 구독/발신할 수 있다. 소규모 친구 그룹 여행 앱 캡스톤 규모에서는 감수 가능한 트레이드오프로 판단하고 v1 범위에서 보강하지 않는다(추후 "방 나가면 roomId 재발급" 등으로 보강 가능).
>
> 근거와 향후 보강 여지는 아래 Self-Review에 남긴다.

- [ ] **Step 1: 의존성 추가**

`server/build.gradle`의 `dependencies` 블록에 추가한다.

```gradle
    implementation 'org.springframework.boot:spring-boot-starter-websocket'
```

- [ ] **Step 2: 실패하는 릴레이 컨트롤러 테스트 작성** `[단위 테스트로 검증 가능]`

이 부분은 실제 WebSocket 연결 없이 순수 Java 객체(메시지 레코드, `SimpMessagingTemplate` 목)로 테스트한다 — `@MessageMapping` 메서드는 일반 메서드 호출과 동일하게 단위 테스트할 수 있다.

`server/src/test/java/com/travelfootsteps/location/LocationRelayControllerTest.java`:

```java
package com.travelfootsteps.location;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import java.security.Principal;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

@ExtendWith(MockitoExtension.class)
class LocationRelayControllerTest {

    @Mock SimpMessagingTemplate messagingTemplate;

    @Test
    void 방_주제로_발신자_uid를_채워_브로드캐스트한다() {
        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        Principal principal = () -> "uid-123";
        LocationMessage message = new LocationMessage("room-1", 37.5, 127.0, 1_700_000_000_000L);

        controller.relay(message, principal);

        verify(messagingTemplate).convertAndSend(eq("/topic/group/room-1/location"),
                eq(new LocationBroadcast("uid-123", 37.5, 127.0, 1_700_000_000_000L)));
    }

    @Test
    void 인증되지_않은_세션의_메시지는_무시한다() {
        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        LocationMessage message = new LocationMessage("room-1", 37.5, 127.0, 1_700_000_000_000L);

        controller.relay(message, null);

        verifyNoInteractions(messagingTemplate);
    }

    @Test
    void roomId가_빈_문자열이면_무시한다() {
        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        Principal principal = () -> "uid-123";
        LocationMessage message = new LocationMessage("", 37.5, 127.0, 1_700_000_000_000L);

        controller.relay(message, principal);

        verifyNoInteractions(messagingTemplate);
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*LocationRelayControllerTest*'
```

기대: 컴파일 실패 — `LocationMessage`, `LocationBroadcast`, `LocationRelayController` 심볼을 찾을 수 없음.

- [ ] **Step 4: 메시지 레코드와 릴레이 컨트롤러 구현**

`server/src/main/java/com/travelfootsteps/location/LocationMessage.java` — 클라이언트가 `SEND /app/location`으로 보내는 바디(Plan D 계약 그대로):

```java
package com.travelfootsteps.location;

public record LocationMessage(String roomId, double lat, double lng, long ts) {
}
```

`server/src/main/java/com/travelfootsteps/location/LocationBroadcast.java` — 서버가 `/topic/group/{roomId}/location`으로 내보내는 바디. Plan D가 이미 클라이언트에서 가정한 `{uid, lat, lng, ts}` 모양과 정확히 일치해야 한다:

```java
package com.travelfootsteps.location;

public record LocationBroadcast(String uid, double lat, double lng, long ts) {
}
```

`server/src/main/java/com/travelfootsteps/location/LocationRelayController.java`:

```java
package com.travelfootsteps.location;

import lombok.RequiredArgsConstructor;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.security.Principal;

/**
 * 그룹 실시간 위치공유의 서버 릴레이. 좌표를 저장하지 않고 같은 방을 구독 중인
 * 클라이언트에게만 즉시 전달한다(스펙 §3, §6-④). 발신자 uid는 클라이언트가
 * 자기 신고로 보내지 않고, StompAuthChannelInterceptor가 세션에 고정해 둔
 * Principal에서 서버가 직접 채운다 — 위조 방지.
 */
@Controller
@RequiredArgsConstructor
public class LocationRelayController {

    private final SimpMessagingTemplate messagingTemplate;

    @MessageMapping("/location")
    public void relay(LocationMessage message, Principal principal) {
        if (principal == null || message.roomId() == null || message.roomId().isBlank()) {
            return; // 인증되지 않았거나 방 정보가 없는 프레임은 조용히 버린다
        }
        LocationBroadcast broadcast = new LocationBroadcast(
                principal.getName(), message.lat(), message.lng(), message.ts());
        messagingTemplate.convertAndSend("/topic/group/" + message.roomId() + "/location", broadcast);
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*LocationRelayControllerTest*'
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 6: 실패하는 STOMP 인증 인터셉터 테스트 작성** `[단위 테스트로 검증 가능]`

`ChannelInterceptor.preSend`는 `Message`/`MessageChannel`만 받는 순수 메서드라 실제 소켓 연결 없이 단위 테스트할 수 있다.

`server/src/test/java/com/travelfootsteps/location/StompAuthChannelInterceptorTest.java`:

```java
package com.travelfootsteps.location;

import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.messaging.support.MessageHeaderAccessor;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

class StompAuthChannelInterceptorTest {

    StubTokenVerifier verifier;
    StompAuthChannelInterceptor interceptor;
    MessageChannel channel;

    @BeforeEach
    void setUp() {
        verifier = new StubTokenVerifier();
        verifier.register("valid-token", "uid-123");
        interceptor = new StompAuthChannelInterceptor(verifier);
        channel = mock(MessageChannel.class);
    }

    private Message<byte[]> connectMessage(String authorizationHeader) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
        if (authorizationHeader != null) {
            accessor.addNativeHeader("Authorization", authorizationHeader);
        }
        accessor.setLeaveMutable(true);
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    @Test
    void 유효한_토큰의_CONNECT는_uid를_Principal로_설정한다() {
        Message<byte[]> message = connectMessage("Bearer valid-token");

        Message<?> result = interceptor.preSend(message, channel);

        StompHeaderAccessor resultAccessor = MessageHeaderAccessor.getAccessor(result, StompHeaderAccessor.class);
        assertThat(resultAccessor.getUser()).isNotNull();
        assertThat(resultAccessor.getUser().getName()).isEqualTo("uid-123");
    }

    @Test
    void 토큰이_없는_CONNECT는_예외를_던진다() {
        Message<byte[]> message = connectMessage(null);

        assertThatThrownBy(() -> interceptor.preSend(message, channel))
                .isInstanceOf(StompAuthenticationException.class);
    }

    @Test
    void 유효하지_않은_토큰의_CONNECT는_예외를_던진다() {
        Message<byte[]> message = connectMessage("Bearer garbage");

        assertThatThrownBy(() -> interceptor.preSend(message, channel))
                .isInstanceOf(StompAuthenticationException.class);
    }

    @Test
    void CONNECT가_아닌_프레임은_그대로_통과시킨다() {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.SEND);
        accessor.setLeaveMutable(true);
        Message<byte[]> message = MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());

        Message<?> result = interceptor.preSend(message, channel);

        assertThat(result).isSameAs(message);
    }
}
```

- [ ] **Step 7: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*StompAuthChannelInterceptorTest*'
```

기대: 컴파일 실패 — `StompAuthChannelInterceptor`, `StompAuthenticationException` 심볼을 찾을 수 없음.

- [ ] **Step 8: 인터셉터·예외·WebSocketConfig 구현**

`server/src/main/java/com/travelfootsteps/location/StompAuthenticationException.java`:

```java
package com.travelfootsteps.location;

public class StompAuthenticationException extends RuntimeException {
    public StompAuthenticationException(String message) {
        super(message);
    }
}
```

`server/src/main/java/com/travelfootsteps/location/StompAuthChannelInterceptor.java`:

```java
package com.travelfootsteps.location;

import com.travelfootsteps.auth.TokenVerifier;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * HTTP FirebaseAuthFilter(Phase 0)는 /ws 핸드셰이크(순수 HTTP Upgrade 요청)까지만
 * 관여하고, 이후 같은 연결 위에서 다중화되는 개별 STOMP 프레임에는 적용되지 않는다.
 * CONNECT 프레임의 Authorization 네이티브 헤더에서 Firebase ID Token을 꺼내
 * TokenVerifier로 검증하고, 성공하면 STOMP 세션의 Principal을 uid로 고정한다 —
 * 이후 같은 세션의 모든 SEND/SUBSCRIBE 프레임이 이 Principal을 그대로 물려받는다.
 */
@Component
@RequiredArgsConstructor
public class StompAuthChannelInterceptor implements ChannelInterceptor {

    private static final String AUTH_HEADER = "Authorization";
    private static final String BEARER_PREFIX = "Bearer ";

    private final TokenVerifier tokenVerifier;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);

        if (accessor != null && StompCommand.CONNECT.equals(accessor.getCommand())) {
            String header = accessor.getFirstNativeHeader(AUTH_HEADER);
            if (header == null || !header.startsWith(BEARER_PREFIX)) {
                throw new StompAuthenticationException("Authorization 헤더가 없습니다");
            }
            String idToken = header.substring(BEARER_PREFIX.length());
            try {
                String uid = tokenVerifier.verifyAndGetUid(idToken);
                accessor.setUser(new UsernamePasswordAuthenticationToken(uid, null, List.of()));
            } catch (TokenVerifier.InvalidTokenException e) {
                throw new StompAuthenticationException("유효하지 않은 토큰입니다");
            }
        }

        return message;
    }
}
```

`server/src/main/java/com/travelfootsteps/location/WebSocketConfig.java`:

```java
package com.travelfootsteps.location;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final StompAuthChannelInterceptor stompAuthChannelInterceptor;

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // SockJS 미사용 — Plan D의 stomp_dart_client가 순수 WebSocket으로 직접 연결한다.
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*");
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic");        // 인메모리 브로커 — 서버 재시작 시 구독 초기화, 저장 없음
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(stompAuthChannelInterceptor);
    }
}
```

> **`/ws`가 SecurityConfig의 인증 대상인가**: Phase 0의 `SecurityConfig`는 `/api/**`에 인증을 요구한다(`/api/health` 제외). `/ws`는 이 패턴 밖이므로 HTTP 레벨에서는 인증 없이 핸드셰이크가 허용되지만, 실제 사용자 식별과 거부는 위 `StompAuthChannelInterceptor`가 CONNECT 프레임에서 전담한다 — 토큰이 없거나 무효하면 연결이 즉시 끊어지므로 결과적으로 미인증 사용자는 `SEND`/`SUBSCRIBE`까지 도달하지 못한다.

- [ ] **Step 9: 테스트 통과 확인 + 전체 회귀 테스트**

```bash
cd server && ./gradlew test --tests '*LocationRelayControllerTest*'
cd server && ./gradlew test --tests '*StompAuthChannelInterceptorTest*'
cd server && ./gradlew test
```

기대: 전부 PASS.

- [ ] **Step 10 (통합 테스트로만 확인 가능 — 수동 검증)**: 실제 STOMP 핸드셰이크와 종단 간 릴레이

위 Step 2~9는 `@MessageMapping` 메서드와 `ChannelInterceptor`를 각각 순수 객체로 단위 테스트했다. 하지만 **"CONNECT 시 인터셉터가 실제로 개입하는지", "SimpleBroker가 실제로 구독자에게 브로드캐스트를 전달하는지"는 실제 WebSocket 연결이 있어야 검증된다** — `WebSocketStompClient` 두 개를 띄워 서로의 위치를 주고받는 통합 테스트를 추가로 작성할 수도 있지만, 이 프로젝트 우선순위(3개월 캡스톤)상 과설계로 보고 아래 수동 시나리오로 대체한다:

```bash
# 서버 기동 후, Plan D Task 8이 만든 GroupLocationMapPage에서
# 위치공유 ON → 다른 계정으로 같은 방에 접속해 상대 마커가 실시간으로 움직이는지 확인.
# 또는 curl 대신 아무 STOMP 클라이언트(예: 브라우저 확장 STOMP 클라이언트)로
# ws://localhost:8080/ws에 Authorization 헤더를 실어 CONNECT → SUBSCRIBE
# /topic/group/room-1/location → 다른 세션에서 SEND /app/location → 수신 확인.
```

- [ ] **Step 11: 커밋**

```bash
git add server/build.gradle server/src/main/java/com/travelfootsteps/location \
  server/src/test/java/com/travelfootsteps/location
git commit -m "feat(server): STOMP 위치 릴레이 — 그룹 실시간 위치공유 서버 릴레이 (저장 없음)"
```

---

### Task 11: 발걸음 체크인·걸음수 동기화 API

> **통합 공백 메모**: Plan C(R3, `2026-09-07-plan-c-map-footsteps.md` Task 6)는 로컬 drift에 쌓인 체크인·걸음수를 서버로 올리는 `POST /api/checkins`, `POST /api/daily-steps`가 존재한다고 가정하고 `DioFootstepsApi` 클라이언트를 이미 작성해 뒀지만, 그 엔드포인트를 만드는 계획이 어디에도 없었다. 스펙 §7의 PostgreSQL 스키마에는 `checkin`, `daily_steps` 테이블이 정의돼 있으므로(이 계획서의 이전 Task까지는 만들지 않았다), 이 Task가 마이그레이션과 엔드포인트를 모두 만든다.

**Files:**
- Create: `server/src/main/resources/db/migration/V7__footsteps.sql`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/Checkin.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/CheckinRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/DailyStep.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/DailyStepRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/CheckinSyncRequest.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/DailyStepSyncRequest.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/SyncResultItem.java`
- Create: `server/src/main/java/com/travelfootsteps/footsteps/FootstepsSyncController.java`
- Test: `server/src/test/java/com/travelfootsteps/footsteps/FootstepsSyncControllerTest.java`

**Interfaces:**
- Consumes: Phase 0의 `CountryRepository`/`TokenVerifier`, Plan C가 이미 클라이언트에서 확정한 계약(`app/lib/features/footsteps/data/footsteps_api.dart`, Plan C 1570~1730줄): `POST /api/checkins` Body `[{localId, lat, lng, countryIso, recordedAt, source}]`(`source ∈ AUTO|MANUAL|IMPORT`), `POST /api/daily-steps` Body `[{localId, date, countryIso, stepCount}]`. 두 응답 모두 `[{localId, serverId}]` — 요청 배열과 같은 순서/개수, `localId`로 매칭한다.
- Produces: 위 두 엔드포인트, **`GET /api/checkins`·`GET /api/daily-steps`(신규, 다기기 복원용 — 아래 참고)**. `V7__footsteps.sql`이 스펙 §7의 `checkin`(`id, firebase_uid, lat, lng, country_id, recorded_at, source`), `daily_steps`(`id, firebase_uid, date, country_id, step_count`) 테이블을 만든다.

> **다기기 복원 지원으로 방침 변경 (2026-09-12 리뷰 반영)**: 이 기능을 다기기 복원(기기 변경/재설치 시 서버에 올려둔 기록을 되찾아오는 것) 용도로 쓰기로 확정했다. 그래서 기존의 "업로드 전용, 멱등성 없음" 설계를 다음처럼 바꾼다.
>
> - **복원용 조회 엔드포인트 추가**: `GET /api/checkins` → 로그인한 사용자의 전체 체크인 `[{id, lat, lng, countryIso, recordedAt, source}]`. `GET /api/daily-steps` → 전체 일별 걸음 수 `[{id, date, countryIso, stepCount}]`. 둘 다 페이지네이션 없이 전체 반환한다(캡스톤 규모의 데이터량이면 충분 — 나중에 사용자당 기록이 많아지면 `since` 파라미터를 추가할 수 있다).
> - **`checkin`에 멱등키 추가**: Plan C의 `localId`는 기기 로컬 drift DB의 자동증가 정수(`c.id`)라 기기마다 값이 겹칠 수 있어 그 자체로는 전역 dedup 키로 쓸 수 없다(요청/응답 매칭 용도로만 그대로 둔다). 대신 이미 요청에 실려 오는 `recordedAt`(체크인이 실제로 발생한 시각, 밀리초 정밀도)을 키로 쓴다 — `UNIQUE (firebase_uid, recorded_at)` 제약을 걸고, 같은 조합이 이미 있으면 새로 만들지 않고 기존 행을 반환한다. 같은 사용자가 정확히 같은 밀리초에 서로 다른 두 곳에서 체크인할 일은 사실상 없으므로 이 정도로 충분하다(Plan C 계약을 바꾸지 않아도 된다). `daily_steps`는 기존처럼 `(firebase_uid, date, country_id)` 유니크 제약 + upsert로 충분하다.
> - **`daily_steps.date`는 UTC가 아니라 클라이언트의 현지 날짜를 그대로 쓴다** — 자세한 이유와 수정은 아래 Step 코드 참고.

- [ ] **Step 1: 마이그레이션**

`server/src/main/resources/db/migration/V7__footsteps.sql`:

```sql
CREATE TABLE checkin (
    id            BIGSERIAL PRIMARY KEY,
    firebase_uid  VARCHAR(128) NOT NULL,
    lat           DOUBLE PRECISION NOT NULL,
    lng           DOUBLE PRECISION NOT NULL,
    country_id    BIGINT NOT NULL REFERENCES country(id),
    recorded_at   TIMESTAMPTZ NOT NULL,
    source        VARCHAR(10) NOT NULL,
    -- 재전송으로 인한 중복 체크인 방지 (2026-09-12 리뷰 반영) — local_id는 기기별 로컬 정수라
    -- 전역 dedup 키로 못 쓰므로, 실제 발생 시각을 키로 쓴다.
    UNIQUE (firebase_uid, recorded_at)
);

CREATE INDEX idx_checkin_firebase_uid ON checkin(firebase_uid);

CREATE TABLE daily_steps (
    id            BIGSERIAL PRIMARY KEY,
    firebase_uid  VARCHAR(128) NOT NULL,
    date          DATE NOT NULL,
    country_id    BIGINT NOT NULL REFERENCES country(id),
    step_count    INTEGER NOT NULL,
    UNIQUE (firebase_uid, date, country_id)
);
```

- [ ] **Step 2: 실패하는 컨트롤러 테스트 작성**

`server/src/test/java/com/travelfootsteps/footsteps/FootstepsSyncControllerTest.java`:

```java
package com.travelfootsteps.footsteps;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(FootstepsSyncControllerTest.TestBeans.class)
class FootstepsSyncControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired CountryRepository countryRepository;
    @Autowired CheckinRepository checkinRepository;
    @Autowired DailyStepRepository dailyStepRepository;

    @Test
    void 체크인_배치를_저장하고_localId_serverId_매핑을_반환한다() throws Exception {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();

        mockMvc.perform(post("/api/checkins")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content("""
                                [
                                  {"localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
                                   "recordedAt": "2026-12-20T09:00:00.000Z", "source": "AUTO"}
                                ]
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].localId").value(1))
                .andExpect(jsonPath("$[0].serverId").isNotEmpty());

        var saved = checkinRepository.findAll();
        assertThat(saved).hasSize(1);
        assertThat(saved.get(0).getFirebaseUid()).isEqualTo("uid-123");
        assertThat(saved.get(0).getCountryId()).isEqualTo(vietnam.getId());
        assertThat(saved.get(0).getSource()).isEqualTo("AUTO");
    }

    @Test
    void 걸음수는_같은_날짜_국가_조합이면_upsert한다() throws Exception {
        String body = """
                [
                  {"localId": 1, "date": "2026-12-20T00:00:00.000Z", "countryIso": "VN", "stepCount": 3000}
                ]
                """;

        mockMvc.perform(post("/api/daily-steps")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content(body))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/daily-steps")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content(body.replace("3000", "5000")))
                .andExpect(status().isOk());

        var all = dailyStepRepository.findAll();
        assertThat(all).hasSize(1);
        assertThat(all.get(0).getStepCount()).isEqualTo(5000);
    }

    @Test
    void 알_수_없는_국가코드는_400을_반환한다() throws Exception {
        mockMvc.perform(post("/api/checkins")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content("""
                                [{"localId": 1, "lat": 0, "lng": 0, "countryIso": "ZZ",
                                  "recordedAt": "2026-12-20T09:00:00.000Z", "source": "MANUAL"}]
                                """))
                .andExpect(status().isBadRequest());
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*FootstepsSyncControllerTest*'
```

기대: 컴파일 실패 — `Checkin`, `CheckinRepository`, `DailyStep`, `DailyStepRepository`, `FootstepsSyncController` 등 심볼을 찾을 수 없음.

- [ ] **Step 4: 엔티티·리포지토리·DTO·컨트롤러 구현**

`server/src/main/java/com/travelfootsteps/footsteps/Checkin.java`:

```java
package com.travelfootsteps.footsteps;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "checkin")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Checkin {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "firebase_uid", nullable = false)
    private String firebaseUid;

    @Column(nullable = false)
    private double lat;

    @Column(nullable = false)
    private double lng;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    // (firebase_uid, recorded_at) 유니크 제약의 기준 컬럼이기도 하다 — 재전송 시 중복 삽입을 막는다.
    @Column(name = "recorded_at", nullable = false)
    private Instant recordedAt;

    @Column(nullable = false, length = 10)
    private String source;

    public static Checkin of(String firebaseUid, double lat, double lng, Long countryId,
                              Instant recordedAt, String source) {
        Checkin checkin = new Checkin();
        checkin.firebaseUid = firebaseUid;
        checkin.lat = lat;
        checkin.lng = lng;
        checkin.countryId = countryId;
        checkin.recordedAt = recordedAt;
        checkin.source = source;
        return checkin;
    }
}
```

`server/src/main/java/com/travelfootsteps/footsteps/CheckinRepository.java`:

```java
package com.travelfootsteps.footsteps;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface CheckinRepository extends JpaRepository<Checkin, Long> {
    Optional<Checkin> findByFirebaseUidAndRecordedAt(String firebaseUid, Instant recordedAt);
    List<Checkin> findByFirebaseUid(String firebaseUid);
}
```

`server/src/main/java/com/travelfootsteps/footsteps/CheckinResponse.java` (복원 조회 응답):

```java
package com.travelfootsteps.footsteps;

import java.time.Instant;

public record CheckinResponse(Long id, double lat, double lng, Long countryId, Instant recordedAt, String source) {
    public static CheckinResponse from(Checkin checkin) {
        return new CheckinResponse(checkin.getId(), checkin.getLat(), checkin.getLng(),
                checkin.getCountryId(), checkin.getRecordedAt(), checkin.getSource());
    }
}
```

`server/src/main/java/com/travelfootsteps/footsteps/DailyStep.java`:

```java
package com.travelfootsteps.footsteps;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

@Entity
@Table(name = "daily_steps",
        uniqueConstraints = @UniqueConstraint(columnNames = {"firebase_uid", "date", "country_id"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class DailyStep {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "firebase_uid", nullable = false)
    private String firebaseUid;

    @Column(nullable = false)
    private LocalDate date;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(name = "step_count", nullable = false)
    private int stepCount;

    public static DailyStep of(String firebaseUid, LocalDate date, Long countryId, int stepCount) {
        DailyStep dailyStep = new DailyStep();
        dailyStep.firebaseUid = firebaseUid;
        dailyStep.date = date;
        dailyStep.countryId = countryId;
        dailyStep.stepCount = stepCount;
        return dailyStep;
    }

    public void updateStepCount(int stepCount) {
        this.stepCount = stepCount;
    }
}
```

`server/src/main/java/com/travelfootsteps/footsteps/DailyStepRepository.java`:

```java
package com.travelfootsteps.footsteps;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface DailyStepRepository extends JpaRepository<DailyStep, Long> {
    Optional<DailyStep> findByFirebaseUidAndDateAndCountryId(String firebaseUid, LocalDate date, Long countryId);
    List<DailyStep> findByFirebaseUid(String firebaseUid);
}
```

`server/src/main/java/com/travelfootsteps/footsteps/DailyStepResponse.java` (복원 조회 응답):

```java
package com.travelfootsteps.footsteps;

import java.time.LocalDate;

public record DailyStepResponse(Long id, LocalDate date, Long countryId, int stepCount) {
    public static DailyStepResponse from(DailyStep dailyStep) {
        return new DailyStepResponse(dailyStep.getId(), dailyStep.getDate(),
                dailyStep.getCountryId(), dailyStep.getStepCount());
    }
}
```

`server/src/main/java/com/travelfootsteps/footsteps/CheckinSyncRequest.java`:

```java
package com.travelfootsteps.footsteps;

import java.time.Instant;

public record CheckinSyncRequest(Long localId, double lat, double lng, String countryIso,
                                   Instant recordedAt, String source) {
}
```

`server/src/main/java/com/travelfootsteps/footsteps/DailyStepSyncRequest.java` — **UTC 변환 제거 (2026-09-12 리뷰 반영)**: `date`를 `Instant`로 받아 `ZoneOffset.UTC`로 자르면, 해외에서 현지 자정을 넘겨도 UTC 기준으로는 아직 전날이라 그날 걸음이 다음날로 잘못 집계될 수 있다. 대신 앱이 "그 걸음을 기록한 현지 달력 날짜"를 `yyyy-MM-dd` 문자열(타임존 없음)로 직접 보내고, 서버는 이를 그대로 저장한다(타임존 변환을 하지 않는다):

```java
package com.travelfootsteps.footsteps;

import java.time.LocalDate;

public record DailyStepSyncRequest(Long localId, LocalDate date, String countryIso, int stepCount) {
}
```

`server/src/main/java/com/travelfootsteps/footsteps/SyncResultItem.java`:

```java
package com.travelfootsteps.footsteps;

public record SyncResultItem(Long localId, String serverId) {
}
```

`server/src/main/java/com/travelfootsteps/footsteps/FootstepsSyncController.java`:

```java
package com.travelfootsteps.footsteps;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class FootstepsSyncController {

    private final CountryRepository countryRepository;
    private final CheckinRepository checkinRepository;
    private final DailyStepRepository dailyStepRepository;

    @PostMapping("/checkins")
    public List<SyncResultItem> syncCheckins(@RequestBody List<CheckinSyncRequest> items,
                                              Authentication authentication) {
        String uid = authentication.getName();
        return items.stream()
                .map(item -> {
                    Country country = findCountryOrThrow(item.countryIso());
                    Checkin saved = upsertCheckin(uid, item, country.getId());
                    return new SyncResultItem(item.localId(), saved.getId().toString());
                })
                .toList();
    }

    @GetMapping("/checkins")
    public List<CheckinResponse> listCheckins(Authentication authentication) {
        return checkinRepository.findByFirebaseUid(authentication.getName()).stream()
                .map(CheckinResponse::from)
                .toList();
    }

    @PostMapping("/daily-steps")
    public List<SyncResultItem> syncDailySteps(@RequestBody List<DailyStepSyncRequest> items,
                                                Authentication authentication) {
        String uid = authentication.getName();
        return items.stream()
                .map(item -> {
                    Country country = findCountryOrThrow(item.countryIso());
                    DailyStep saved = upsertDailyStep(uid, item.date(), country.getId(), item.stepCount());
                    return new SyncResultItem(item.localId(), saved.getId().toString());
                })
                .toList();
    }

    @GetMapping("/daily-steps")
    public List<DailyStepResponse> listDailySteps(Authentication authentication) {
        return dailyStepRepository.findByFirebaseUid(authentication.getName()).stream()
                .map(DailyStepResponse::from)
                .toList();
    }

    // (uid, recordedAt) 유니크 제약 덕분에 같은 이벤트가 재전송돼도 새 행을 만들지 않고
    // 기존 행을 그대로 반환한다 — 네트워크 재시도로 인한 중복 체크인을 막는다.
    private Checkin upsertCheckin(String uid, CheckinSyncRequest item, Long countryId) {
        return checkinRepository.findByFirebaseUidAndRecordedAt(uid, item.recordedAt())
                .orElseGet(() -> checkinRepository.save(Checkin.of(uid,
                        item.lat(), item.lng(), countryId, item.recordedAt(), item.source())));
    }

    private DailyStep upsertDailyStep(String uid, LocalDate date, Long countryId, int stepCount) {
        return dailyStepRepository.findByFirebaseUidAndDateAndCountryId(uid, date, countryId)
                .map(existing -> {
                    existing.updateStepCount(stepCount);
                    return existing;
                })
                .orElseGet(() -> dailyStepRepository.save(DailyStep.of(uid, date, countryId, stepCount)));
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "알 수 없는 국가 코드: " + iso2));
    }
}
```

- [ ] **Step 5: 테스트 통과 확인 + 전체 회귀 테스트**

```bash
cd server && ./gradlew test --tests '*FootstepsSyncControllerTest*'
cd server && ./gradlew test
```

기대: 전부 PASS.

- [ ] **Step 6: 커밋**

```bash
git add server/src/main/resources/db/migration/V7__footsteps.sql \
  server/src/main/java/com/travelfootsteps/footsteps \
  server/src/test/java/com/travelfootsteps/footsteps
git commit -m "feat(server): 발걸음 체크인·걸음수 배치 동기화 API (checkin, daily_steps)"
```

---

## Self-Review

**1. 스펙 커버리지**

| 스펙 항목 | 담당 Task |
|---|---|
| §4 입국허가요건 API + 자연어 파서 | Task 2, 3 |
| §4 여행경보/재외공관 API | Task 4 |
| §4 한국수출입은행 환율 API | Task 9 |
| §4 Google Cloud Translation (인터페이스 추상화) | Task 8 |
| §5 Tier A/B — 배치는 전 국가, verified 플래그로 Tier A 보존 | Task 3(Collector의 verified 분기), Task 4(스케줄러가 전 국가 순회) |
| §6-① 비자 판정 로직 4단계 + 역산 일정 | Task 5 |
| §6-⑥ 여행경보/공관 프록시 (기본형) | Task 4 |
| §6-⑦ 환율 표시 + 환전 알림 | Task 9 |
| §7 API 목록 전체 (`/api/countries/{iso2}`, `/checklist`, `/alerts`, `/embassies`, `/trips`, `/translate`, `/places/nearby`, `/exchange-rates/{code}`) | Task 3(alerts/embassies 데이터 소스), Task 4, 6, 7, 8, 9 |
| §7 데이터 모델(`visa_requirement`, `travel_alert`, `embassy`, `trip`, `trip_task`, `checklist_template`, `exchange_rate`) | Task 3~7, 9 마이그레이션 |
| §12 "번역 NMT 기본 + 인터페이스 추상화" | Task 8 `TranslationClient` |
| §7 STOMP 계약(`WS /ws`, `SEND /app/location`, `SUBSCRIBE /topic/group/{roomId}/location`), §8 R1 역할분담의 "WebSocket 위치 릴레이" | Task 10 |
| §7 데이터 모델(`checkin`, `daily_steps`) + 발걸음 동기화 API | Task 11 |

빠진 항목: 없음. 다만 `visa_requirement.passport_type`의 `OFFICIAL`/`DIPLOMATIC` 값은 스키마 컬럼만 만들고 실제 수집·판정 로직은 이번 계획에 없다 — Global Constraints에서 명시적으로 범위 밖으로 선언했다.

**2. 플레이스홀더 스캔**

전체 Task를 다시 훑어 "TODO", "나중에 구현" 류의 표현이 없는지 확인했다. Task 5 Step 7의 초안에 있던 잘못된 어서션 줄은 작성 중 발견해 즉시 정리했다(현재 파일에는 남아 있지 않다). 모든 코드 스텝에 실제 컴파일 가능한 코드가 포함되어 있다.

**3. 타입/시그니처 일관성**

- `VisaVerdict.wireValue()`가 Task 5, Task 6(`VisaResultResponse.from`)에서 동일하게 `"VISA_FREE_OK"` 등 문자열을 반환하며, Plan B의 `VisaVerdict.fromWire`가 기대하는 값과 정확히 일치한다.
- `VisaJudgement`의 필드명(`stayDays`, `visaFreeDays`, `passportOk`, `passportValidityMonths`, `passportShortfallDays`)이 Task 5→6에서 그대로 이어지고, `VisaResultResponse`가 같은 이름으로 JSON에 노출되어 Plan B의 `VisaResult.fromJson`과 일치한다.
- `ScheduleGenerator.GeneratedTask(title, dueDate)`가 Task 5에서 정의되고 Task 6의 `TripController.create()`에서 그대로 소비된다.
- `CountryDetailResponse`/`ChecklistTemplateResponse`/`TravelAlertResponse`/`EmbassyResponse`/`PlaceResponse`/`TranslateResponse`/`ExchangeRateResponse`의 필드명이 각각 Plan B/F/E가 명시한 JSON 키와 일치한다(Global Constraints 표에서 다시 확인).

**4. 이 계획서 작성 중 스스로 내린 판단과, 원 지시와 다르게 해석한 지점**

- **범위를 원 지시보다 넓혔다.** 원 지시는 "trips API, 번역 프록시, Places 프록시, 환율 캐시"까지만 나열했지만, 이미 작성된 Plan B/F가 `GET /api/countries/{iso2}`, `/checklist`, `/alerts`, `/embassies`를 Plan A(R1)의 산출물로 이미 가정하고 있었다. 이 네 엔드포인트를 만들지 않으면 Plan B/F가 그대로 깨지므로 Task 4, 7에 포함시켰다. **원 지시자에게 확인이 필요한 지점**: 이 네 엔드포인트가 실제로 Plan A의 책임이 맞는지, 혹은 별도 계획서로 분리할 계획이었는지.
- **`verified=true`로 전환하는 메커니즘을 만들지 않았다.** 스펙은 "Tier A는 수기 검증"이라고만 하고 그 검증을 반영하는 인터페이스를 정의하지 않는다. 이 계획은 배치가 검증된 행을 보존하는 쪽만 구현하고, 검증 자체(관리자 화면이나 스크립트)는 범위 밖으로 뒀다. R4가 Tier A 데이터를 검증할 때 DB를 직접 갱신(`UPDATE visa_requirement SET visa_required=..., visa_free_days=..., verified=true WHERE ...`)하는 수작업이 필요하다 — 이 계획서 밖에서 별도로 안내해야 한다.
- **환전 알림(FCM)의 우선순위를 캐시/조회 API보다 낮게 재배치했다.** 스펙 §6-⑦은 환율 표시와 환전 알림을 함께 서술하지만, 알림은 Firestore 접근·FCM 발송이라는 추가 인프라가 필요해 실패 지점이 늘어난다. T3 안에서도 캐시 조회가 앱 화면(Plan B)에 직접 쓰이는 반면 알림은 부가 기능이라 판단해 Step 9~10으로 분리하고 생략 가능하다고 명시했다.
- **일반여권만 다루기로 범위를 좁혔다.** 스펙 §6-①의 판정 로직 설명이 일반여권 기준이라 이 계획의 배치·판정 엔진도 `passport_type=GENERAL`만 채운다. 관용/외교관 여권은 컬럼만 존재하고 실제 파이프라인은 없다.
- **파서 테스트가 실제 API 응답으로 검증되지 않은 채로 작성됐다.** Phase 0 Task 2(공공데이터포털 활용신청)가 이 계획서 작성 시점에 아직 완료되지 않았을 수 있어, Task 2의 테스트 케이스는 스펙에 인용된 문구 1개와 합리적으로 추정한 문구들로 구성했다. Task 3 착수 시 실제 응답을 반드시 추가로 확보해 파서 테스트를 보강해야 한다 — Global Constraints에 이 경고를 명시했다.

**5. 추가 통합 — Task 10, 11 (병렬 계획서 작성으로 생긴 공백 메우기)**

Plan A와 Plan D, Plan A와 Plan C를 각각 독립적인 서브에이전트가 병렬로 작성하면서 서로 상대방 책임이라고 미룬 두 기능이 있었다. 원 지시에 따라 이 계획서에 아래 두 Task를 추가했다.

- **Task 10(WebSocket 위치 릴레이)**: 최초 이 계획은 "Plan D가 만들 것"이라 가정하고 명시적으로 범위 밖으로 선언했으나, 스펙 §8 역할분담 표가 이미 이 릴레이를 R1(백엔드, 즉 이 계획) 책임으로 못 박고 있었고 Plan D는 반대로 "Plan A가 이미 존재한다"고 가정하고 Flutter STOMP 클라이언트만 작성해 뒀다. 두 계획서가 서로 미룬 것이므로 스펙의 역할분담을 근거로 이 계획에 추가하는 것이 맞다고 판단했다. **Plan D와 대조 확인**: Plan D의 `location_share_client.dart`(2413~2444줄)가 실제로 보내는 SEND 바디는 `{roomId, lat, lng, ts}`, 기대하는 SUBSCRIBE 브로드캐스트 바디는 `{uid, lat, lng, ts}` — Task 10의 `LocationMessage`/`LocationBroadcast` 레코드 필드를 이 계약과 정확히 맞췄다. Plan D 코드 주석(2469줄)이 "서버가 uid를 안 넣으면 클라이언트가 모든 이벤트를 조용히 버린다"고 명시적으로 경고하고 있어, `LocationRelayController`가 클라이언트 자기 신고가 아니라 STOMP 세션 Principal(`StompAuthChannelInterceptor`가 CONNECT 프레임에서 설정)에서 uid를 채워 넣도록 구현했다. HTTP `FirebaseAuthFilter`는 `/ws` 핸드셰이크에는 관여하지만 그 위에서 다중화되는 개별 STOMP 프레임 인증까지는 커버하지 못한다는 점을 반영해 별도 `ChannelInterceptor`를 뒀다. 그룹 멤버십(Firestore `rooms/{roomId}.participants[]`) 검증은 의도적으로 생략했다 — Firebase Admin SDK로 매 프레임마다 Firestore를 왕복 조회하는 비용이 3개월 캡스톤 규모에는 과하다고 판단했고, "인증된 사용자 + roomId를 아는 사람만 접근 가능"이라는 최소 보장으로 v1을 충분하다고 봤다. 필요하면 이후 Firestore 멤버십 체크를 `LocationRelayController.relay()`에 한 줄 추가하는 정도로 보강 가능하도록 경계를 열어 뒀다.
- **Task 11(발걸음 동기화 API)**: Plan C Task 6(`footsteps_sync_service.dart`)가 `POST /api/checkins`, `POST /api/daily-steps`가 존재한다고 가정하고 `DioFootstepsApi` 클라이언트를 이미 확정해 뒀지만, 두 엔드포인트를 만드는 계획이 어디에도 없었다. 스펙 §7의 `checkin`/`daily_steps` 테이블도 이 계획의 이전 마이그레이션(V2~V6)에 포함되지 않았으므로, 이 계획이 테이블·엔티티·API를 전부 새로 추가하는 것이 자연스럽다고 판단했다. **Plan C와 대조 확인**: Plan C의 `DioFootstepsApi.pushCheckins`/`pushDailySteps`(1683~1729줄)가 실제로 보내는 요청 바디는 `[{localId, lat, lng, countryIso, recordedAt, source}]`와 `[{localId, date, countryIso, stepCount}]`이고, 로컬 id → 서버 id 매핑을 응답 `[{localId, serverId}]`로 기대한다 — Task 11의 `CheckinSyncRequest`/`DailyStepSyncRequest`/`SyncResultItem` 필드명을 이 계약과 정확히 맞췄다. `source`는 Plan C가 `c.source.name.toUpperCase()`로 `AUTO`/`MANUAL`/`IMPORT` 문자열을 보내며, 스펙 §7의 `checkin.source(AUTO|MANUAL|IMPORT)` 값과 일치한다. `daily_steps`는 `(firebase_uid, date, country_id)` 유니크 제약 + upsert로 중복 삽입에 의한 걸음 수 부풀림을 막았다. `checkin`도 최초에는 단순 삽입(dedup 없음)으로 설계했으나, 2026-09-12 리뷰에서 발걸음 서버 동기화를 다기기 복원 용도로 쓰기로 확정하면서 `(firebase_uid, recorded_at)` 유니크 제약 + upsert로 재전송 멱등성을 추가했다 — 자세한 내용은 Task 11 본문 참고.

---

**계획 완료.** 총 11개 Task(핵심 6기능 대응 Task 1~8, 10, T3 확장 Task 9, 통합 공백 보강 Task 11), 예상 기간 W3~W7 (스펙 §12 일정표 기준). 실행은 `superpowers:subagent-driven-development`(Task별 신선한 서브에이전트 + 2단계 리뷰) 또는 `superpowers:executing-plans`(이 세션에서 배치 실행)를 선택해 진행한다.
