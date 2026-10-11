# 지갑 1단계 — 서버 환율 파이프라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서버 환율 캐시가 실제로 채워지고(지금은 0행), 전 영업일 대비 등락과 출처를 함께 내려주며, 백그라운드 앱도 로그인 없이 조회할 수 있게 한다.

**Architecture:** 기존 `com.travelfootsteps.exchangerate` 패키지를 고쳐 쓴다. `exchange_rate`는 통화당 한 행을 유지하되 직전 고시일 값 한 칸(`previous_*`)과 출처(`source`)를 추가한다. 배치는 수출입은행(EXIM)을 먼저 적용하고, 수출입은행이 고시하지 않는 통화만 `open.er-api.com`(ER_API)으로 채운다. 기동 시 캐시가 비어 있으면 최근 영업일 2개를 거슬러 올라가 채운다.

**Tech Stack:** Java 21, Spring Boot(Web, Data JPA, Security, Scheduling, Retry), Flyway, PostgreSQL 16, JUnit 5 + Mockito + AssertJ, MockRestServiceServer, Testcontainers.

**Spec:** `docs/superpowers/specs/2026-10-09-wallet-exchange-alerts-design.md` §4

## Global Constraints

- 작업 브랜치는 `wallet`. 커밋 메시지에 `Co-Authored-By`·Claude·AI 관련 트레일러를 절대 넣지 않는다(CLAUDE.md 기여자 비노출).
- `server/src/main/**` 프로덕션 코드에는 Spring 개념을 처음 배우는 사람이 이해할 수 있는 설명 주석을 단다(애너테이션의 역할, 요청-응답 흐름에서의 위치). 테스트 코드에는 이 규칙을 적용하지 않는다.
- `krw_rate`·`previous_krw_rate`는 항상 **통화 1단위당 원화**, `NUMERIC(18, 6)`. 나눗셈은 소수 6자리 `RoundingMode.HALF_UP`.
- `changePercent` = `(krwRate − previousKrwRate) / previousKrwRate × 100`, 소수 2자리 `HALF_UP`. 이전값이 없거나 0이면 `null`.
- 날짜 계산은 `ZoneId.of("Asia/Seoul")`(KST) 기준. `LocalDate.now()`를 인자 없이 쓰지 않는다.
- 응답 필드명(정확히): `currencyCode`, `krwRate`, `baseDate`, `previousKrwRate`, `previousBaseDate`, `changePercent`, `source`. `source` 값은 `"EXIM"` 또는 `"ER_API"`.
- 수출입은행 실측 사실(2026-10-08·09): 필드명 `result`·`cur_unit`·`deal_bas_r` 확인, `result=1`이 성공. 비영업일·영업일 11시 이전에는 빈 배열 `[]`. `deal_bas_r`은 `"1,339.2"`처럼 콤마가 섞인 문자열. 응답에 `KRW` 항목이 포함된다(저장하지 않는다).
- 테스트는 외부 API를 절대 호출하지 않는다. 클라이언트는 Mockito 목 또는 `MockRestServiceServer`로 대체하고, 기동 시 보정 러너는 `@Profile("!test")`로 테스트에서 빠진다.
- `@SpringBootTest` 테스트(`ExchangeRateControllerTest`)는 Testcontainers라서 **Docker Desktop이 켜져 있어야** 로컬에서 돈다. Docker가 없으면 그 테스트만 CI에 맡기고 나머지 단위 테스트로 검증한다.
- 명령은 모두 `server/` 디렉터리에서 실행한다.

## File Structure

| 파일 | 상태 | 책임 |
|---|---|---|
| `server/src/main/resources/db/migration/V10__exchange_rate_previous.sql` | 생성 | 정밀도 확장, `previous_*`·`source` 컬럼 |
| `server/src/main/java/com/travelfootsteps/exchangerate/RateSource.java` | 생성 | 출처 enum(`EXIM`, `ER_API`) |
| `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRate.java` | 수정 | 새 컬럼 매핑, `apply()` 갱신 규칙, `changePercent()` |
| `server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiResponse.java` | 생성 | `open.er-api.com` 응답 매핑 |
| `server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiClient.java` | 생성 | `open.er-api.com` 호출 |
| `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateRepository.java` | 수정 | 보정 실행 판단 쿼리 메서드 |
| `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java` | 수정(재작성) | 스케줄, 두 소스 적용, 보정 실행 |
| `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateStartupBackfill.java` | 생성 | 기동 시 보정 실행 러너 |
| `server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximClient.java` | 수정 | 안 쓰게 된 `fetchTodayRates()` 삭제 |
| `server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximApiItem.java` | 수정 | "검증 필요" 주석을 실측 결과로 교체 |
| `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateResponse.java` | 수정 | 응답 필드 4개 추가 |
| `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateController.java` | 수정 | 인증 관련 주석만 갱신 |
| `server/src/main/java/com/travelfootsteps/auth/SecurityConfig.java` | 수정 | `GET /api/exchange-rates/**` 허용 |
| `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateTest.java` | 생성 | 엔티티 갱신 규칙·등락률 |
| `server/src/test/java/com/travelfootsteps/exchangerate/OpenErApiClientTest.java` | 생성 | ER_API 응답 파싱·오류 |
| `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateBatchSchedulerTest.java` | 수정(재작성) | 배치·보정 실행 |
| `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateControllerTest.java` | 수정 | 새 필드, 토큰 없이 200, 다른 API는 401 |

---

### Task 1: 스키마 확장 + `ExchangeRate` 갱신 규칙

**Files:**
- Create: `server/src/main/resources/db/migration/V10__exchange_rate_previous.sql`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/RateSource.java`
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRate.java` (전체 교체)
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java` (`upsert()` 안의 한 줄)
- Test: `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateTest.java`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum RateSource { EXIM, ER_API }`
  - `static ExchangeRate ExchangeRate.of(String currencyCode, BigDecimal krwRate, LocalDate baseDate, RateSource source)`
  - `static ExchangeRate ExchangeRate.of(String currencyCode, BigDecimal krwRate, LocalDate baseDate)` (출처 `EXIM`)
  - `void ExchangeRate.apply(BigDecimal rate, LocalDate date, RateSource source)`
  - `BigDecimal ExchangeRate.changePercent()` (null 가능)
  - 게터(Lombok): `getCurrencyCode()`, `getKrwRate()`, `getBaseDate()`, `getPreviousKrwRate()`, `getPreviousBaseDate()`, `getSource()`
  - 기존 `update(BigDecimal, LocalDate)`는 **삭제**된다.

- [ ] **Step 1: 실패하는 엔티티 테스트 작성**

`server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateTest.java`:

```java
package com.travelfootsteps.exchangerate;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class ExchangeRateTest {

    static final LocalDate D6 = LocalDate.of(2026, 10, 6);
    static final LocalDate D7 = LocalDate.of(2026, 10, 7);
    static final LocalDate D8 = LocalDate.of(2026, 10, 8);

    @Test
    void 더_늦은_고시일이_오면_기존값을_이전값으로_밀어낸다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);

        rate.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);

        assertThat(rate.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(rate.getBaseDate()).isEqualTo(D8);
        assertThat(rate.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(rate.getPreviousBaseDate()).isEqualTo(D7);
    }

    @Test
    void 같은_고시일이면_현재값만_바꾸고_이전값은_유지한다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);

        rate.apply(new BigDecimal("1340.0"), D8, RateSource.EXIM);

        assertThat(rate.getKrwRate()).isEqualByComparingTo("1340.0");
        assertThat(rate.getBaseDate()).isEqualTo(D8);
        assertThat(rate.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(rate.getPreviousBaseDate()).isEqualTo(D7);
    }

    @Test
    void 더_이른_고시일은_이전값이_비어_있을_때만_채운다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D8, RateSource.EXIM);

        rate.apply(new BigDecimal("1333.6"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1300.0"), D6, RateSource.EXIM);

        assertThat(rate.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(rate.getBaseDate()).isEqualTo(D8);
        assertThat(rate.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(rate.getPreviousBaseDate()).isEqualTo(D7);
    }

    @Test
    void 등락률은_소수_둘째자리까지_반올림한다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);

        assertThat(rate.changePercent()).isEqualByComparingTo("0.42");
    }

    @Test
    void 하락하면_등락률이_음수다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1333.6"), D8, RateSource.EXIM);

        assertThat(rate.changePercent()).isEqualByComparingTo("-0.42");
    }

    @Test
    void 이전값이_없으면_등락률은_null이다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D8, RateSource.EXIM);

        assertThat(rate.changePercent()).isNull();
    }

    @Test
    void 출처를_생략하면_수출입은행으로_본다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D8);

        assertThat(rate.getSource()).isEqualTo(RateSource.EXIM);
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.ExchangeRateTest'`
Expected: FAIL — 컴파일 에러 `cannot find symbol: class RateSource` (그리고 `apply`, `changePercent` 없음)

- [ ] **Step 3: 마이그레이션 작성**

`server/src/main/resources/db/migration/V10__exchange_rate_previous.sql`:

```sql
-- 지갑·환율 알림 설계 §4.2. 전 영업일 대비 등락을 계산하려면 "직전 고시일" 값이 필요하다.
-- 이력 테이블을 만들지 않고 직전 값 한 칸(previous_*)만 둔다 — 화면과 알림이 쓰는 건 "오늘 vs 직전 영업일" 뿐이다.
-- krw_rate의 소수 자릿수를 4 → 6으로 넓히는 이유: VND(약 0.0519원)·IDR처럼 1단위 환율이 아주 작은
-- 통화는 4자리면 유효숫자가 3자리뿐이라 하루 등락 %가 거칠게 나온다.
-- source: 값의 출처. EXIM(한국수출입은행 고시환율) 또는 ER_API(open.er-api.com 참고환율).
ALTER TABLE exchange_rate ALTER COLUMN krw_rate TYPE NUMERIC(18, 6);
ALTER TABLE exchange_rate ADD COLUMN previous_krw_rate  NUMERIC(18, 6);
ALTER TABLE exchange_rate ADD COLUMN previous_base_date DATE;
ALTER TABLE exchange_rate ADD COLUMN source VARCHAR(10) NOT NULL DEFAULT 'EXIM';
```

- [ ] **Step 4: `RateSource` 작성**

`server/src/main/java/com/travelfootsteps/exchangerate/RateSource.java`:

```java
package com.travelfootsteps.exchangerate;

// 환율 값이 어느 외부 소스에서 왔는지를 나타낸다.
// - EXIM: 한국수출입은행 고시환율(매매기준율). 영업일 11시 전후에 하루 한 번 갱신된다.
// - ER_API: open.er-api.com 참고환율. 수출입은행이 고시하지 않는 통화(VND, TWD, PHP, TRY, CZK, CNY)만
//   이 값으로 채운다. 은행 고시환율이 아니므로 앱은 "참고환율"과 출처 문구를 함께 보여준다.
// 앱이 출처 표기를 고를 수 있게 응답(ExchangeRateResponse.source)에도 이 이름이 그대로 실린다.
public enum RateSource {
    EXIM,
    ER_API
}
```

- [ ] **Step 5: `ExchangeRate` 전체 교체**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRate.java`:

```java
package com.travelfootsteps.exchangerate;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

// @Entity + @Table(name = "exchange_rate"): V6__exchange_rate.sql(+ V10에서 컬럼 추가)의 exchange_rate
// 테이블과 매핑되는 JPA 엔티티다. 통화코드(currency_code)당 딱 한 행만 존재하는 캐시이고(UNIQUE 제약),
// 이력 대신 "직전 고시일 값" 한 칸(previousKrwRate/previousBaseDate)만 들고 있다 — 전 영업일 대비
// 등락을 계산하는 데는 그 한 칸이면 충분하다(지갑·환율 알림 설계 §4.2).
// @NoArgsConstructor(access = PROTECTED): JPA가 리플렉션으로 인스턴스를 생성할 때 필요한
// 기본 생성자다. 외부 코드가 `new ExchangeRate()`로 빈 객체를 만들 수 없도록 protected로 좁혔다.
@Entity
@Table(name = "exchange_rate")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ExchangeRate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // CHAR(3)로 매핑하는 이유는 Country.isoAlpha2/isoAlpha3 필드의 주석과 동일하다 —
    // columnDefinition만으로는 DDL 생성 문자열만 바뀌고 Hibernate 내부 타입 코드는 VARCHAR로
    // 남아, ddl-auto=validate가 실제 DB의 CHAR(bpchar) 컬럼과 비교할 때 SchemaManagementException을
    // 던진다. @JdbcTypeCode(SqlTypes.CHAR)를 함께 붙여야 검증이 통과한다.
    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "currency_code", nullable = false, unique = true, length = 3, columnDefinition = "CHAR(3)")
    private String currencyCode;

    // 항상 "통화 1단위당 원화"다. 수출입은행의 JPY(100)·IDR(100)은 배치가 100으로 나눠서 넣는다.
    @Column(name = "krw_rate", nullable = false, precision = 18, scale = 6)
    private BigDecimal krwRate;

    // 이 환율이 고시된 날짜(영업일). 배치를 돌린 날짜가 아니다.
    @Column(name = "base_date", nullable = false)
    private LocalDate baseDate;

    // 직전 고시일의 환율과 그 날짜. 아직 하루치만 받았으면 null이고, 이때 등락은 계산하지 않는다.
    @Column(name = "previous_krw_rate", precision = 18, scale = 6)
    private BigDecimal previousKrwRate;

    @Column(name = "previous_base_date")
    private LocalDate previousBaseDate;

    // @Enumerated(EnumType.STRING): enum을 DB에 "EXIM" 같은 이름 문자열로 저장한다.
    // 기본값(ORDINAL)은 0, 1 같은 순서 번호로 저장해서, 나중에 enum 순서가 바뀌면 기존 데이터의
    // 의미가 조용히 뒤바뀐다 — 그래서 문자열 저장을 명시한다.
    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, length = 10)
    private RateSource source;

    // 새 통화의 첫 캐시 행을 만드는 정적 팩토리 메서드. 배치가 아직 캐시에 없는 통화코드를
    // 만나면 이 메서드로 새 행을 만들어 저장한다.
    public static ExchangeRate of(String currencyCode, BigDecimal krwRate, LocalDate baseDate, RateSource source) {
        ExchangeRate rate = new ExchangeRate();
        rate.currencyCode = currencyCode;
        rate.krwRate = krwRate;
        rate.baseDate = baseDate;
        rate.source = source;
        return rate;
    }

    // 출처를 생략하면 수출입은행 값으로 본다(기존 호출부·테스트 호환).
    public static ExchangeRate of(String currencyCode, BigDecimal krwRate, LocalDate baseDate) {
        return of(currencyCode, krwRate, baseDate, RateSource.EXIM);
    }

    /**
     * 새로 받은 환율을 이 캐시 행에 반영한다(설계 §4.3).
     *
     * <ul>
     *   <li>더 늦은 고시일: 지금 값을 이전값 칸으로 밀어내고 새 값을 현재값으로 삼는다.</li>
     *   <li>같은 고시일: 같은 날 배치가 여러 번 돌았거나 값이 정정된 경우다. 현재값만 바꾸고 이전값은 둔다.</li>
     *   <li>더 이른 고시일: 기동 시 보정 실행이 과거 영업일을 채울 때다. 이전값 칸이 비어 있을 때만 채운다.</li>
     * </ul>
     *
     * <p>JPA 영속성 컨텍스트 안에서 필드만 바꾸면 트랜잭션 커밋 시점에 변경 감지(dirty checking)로
     * 자동 UPDATE 되므로, 이 메서드를 부른 쪽은 별도로 save()를 호출할 필요가 없다.
     */
    public void apply(BigDecimal rate, LocalDate date, RateSource source) {
        if (date.isAfter(baseDate)) {
            this.previousKrwRate = this.krwRate;
            this.previousBaseDate = this.baseDate;
            this.krwRate = rate;
            this.baseDate = date;
            this.source = source;
        } else if (date.isEqual(baseDate)) {
            this.krwRate = rate;
            this.source = source;
        } else if (this.previousBaseDate == null) {
            this.previousKrwRate = rate;
            this.previousBaseDate = date;
        }
    }

    // 전 영업일 대비 등락률(%). 소수 둘째 자리 반올림. 이전값이 없거나 0이면 계산할 수 없어 null.
    public BigDecimal changePercent() {
        if (previousKrwRate == null || previousKrwRate.signum() == 0) {
            return null;
        }
        return krwRate.subtract(previousKrwRate)
                .multiply(BigDecimal.valueOf(100))
                .divide(previousKrwRate, 2, RoundingMode.HALF_UP);
    }
}
```

- [ ] **Step 6: 삭제된 `update()`를 쓰던 배치의 한 줄 교체**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java`의 `upsert()` 안:

```java
                        existing -> existing.update(rate, baseDate),
```

를 다음으로 바꾼다(배치 전체는 Task 3에서 다시 쓴다. 지금은 컴파일만 되게 한다):

```java
                        existing -> existing.apply(rate, baseDate, RateSource.EXIM),
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.ExchangeRateTest' --tests 'com.travelfootsteps.exchangerate.ExchangeRateBatchSchedulerTest'`
Expected: PASS (ExchangeRateTest 7개, 기존 ExchangeRateBatchSchedulerTest 4개)

- [ ] **Step 8: 커밋**

```bash
git add server/src/main/resources/db/migration/V10__exchange_rate_previous.sql \
  server/src/main/java/com/travelfootsteps/exchangerate/RateSource.java \
  server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRate.java \
  server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java \
  server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateTest.java
git commit -m "feat(server): 환율 캐시에 직전 고시일 값과 출처를 저장한다"
```

---

### Task 2: `open.er-api.com` 클라이언트

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiClient.java`
- Test: `server/src/test/java/com/travelfootsteps/exchangerate/OpenErApiClientTest.java`

**Interfaces:**
- Consumes: `com.travelfootsteps.externaldata.ExternalApiException` (기존, 생성자 `(String)`, `(String, Throwable)`)
- Produces:
  - `record OpenErApiResponse(String result, long timeLastUpdateUnix, Map<String, BigDecimal> rates)` — `rates`는 "1원 = 몇 단위"(KRW 기준)
  - `OpenErApiClient(RestClient.Builder builder)`
  - `OpenErApiResponse OpenErApiClient.fetchKrwBase()` — 실패 시 `ExternalApiException`

- [ ] **Step 1: 실패하는 클라이언트 테스트 작성**

`server/src/test/java/com/travelfootsteps/exchangerate/OpenErApiClientTest.java`:

```java
package com.travelfootsteps.exchangerate;

import com.travelfootsteps.externaldata.ExternalApiException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class OpenErApiClientTest {

    @Test
    void KRW_기준_환율과_갱신_시각을_읽는다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        OpenErApiClient client = new OpenErApiClient(builder);

        server.expect(requestTo("https://open.er-api.com/v6/latest/KRW"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"result":"success","base_code":"KRW","time_last_update_unix":1791504151,
                         "rates":{"KRW":1,"VND":19.255146,"TWD":0.023826}}
                        """, MediaType.APPLICATION_JSON));

        OpenErApiResponse response = client.fetchKrwBase();

        assertThat(response.timeLastUpdateUnix()).isEqualTo(1791504151L);
        assertThat(response.rates().get("VND")).isEqualByComparingTo("19.255146");
        assertThat(response.rates().get("TWD")).isEqualByComparingTo("0.023826");
        server.verify();
    }

    @Test
    void result가_success가_아니면_ExternalApiException을_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        OpenErApiClient client = new OpenErApiClient(builder);

        server.expect(requestTo("https://open.er-api.com/v6/latest/KRW"))
                .andRespond(withSuccess("{\"result\":\"error\",\"error-type\":\"unsupported-code\"}",
                        MediaType.APPLICATION_JSON));

        assertThatThrownBy(client::fetchKrwBase).isInstanceOf(ExternalApiException.class);
    }

    @Test
    void HTTP_오류면_ExternalApiException을_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        OpenErApiClient client = new OpenErApiClient(builder);

        server.expect(requestTo("https://open.er-api.com/v6/latest/KRW")).andRespond(withServerError());

        assertThatThrownBy(client::fetchKrwBase).isInstanceOf(ExternalApiException.class);
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.OpenErApiClientTest'`
Expected: FAIL — 컴파일 에러 `cannot find symbol: class OpenErApiClient`

- [ ] **Step 3: 응답 레코드 작성**

`server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiResponse.java`:

```java
package com.travelfootsteps.exchangerate;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;
import java.util.Map;

// open.er-api.com/v6/latest/KRW 응답에서 이 서버가 쓰는 세 필드만 매핑한 레코드다.
// - result: 성공이면 "success". 실패하면 "error"와 함께 error-type이 온다.
// - time_last_update_unix: 이 환율이 갱신된 시각(UTC 유닉스 초). 배치가 이걸 KST 날짜로 바꿔 baseDate로 쓴다.
// - rates: KRW 기준이라 "1원 = 몇 단위"다(예: VND 19.255146). 원화 환율은 배치가 1 / rates[code]로 뒤집는다.
// @JsonIgnoreProperties(ignoreUnknown = true): provider, terms_of_use 등 쓰지 않는 필드는 무시한다.
// @JsonProperty: API의 스네이크케이스 필드명을 자바 관례 이름에 연결한다.
@JsonIgnoreProperties(ignoreUnknown = true)
public record OpenErApiResponse(
        @JsonProperty("result") String result,
        @JsonProperty("time_last_update_unix") long timeLastUpdateUnix,
        @JsonProperty("rates") Map<String, BigDecimal> rates
) {
}
```

- [ ] **Step 4: 클라이언트 작성**

`server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiClient.java`:

```java
package com.travelfootsteps.exchangerate;

import com.travelfootsteps.externaldata.ExternalApiException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * open.er-api.com 무료(Open Access) 환율 API 클라이언트. 한국수출입은행이 고시하지 않는 통화
 * (VND, TWD, PHP, TRY, CZK, CNY)의 참고환율을 받아오는 데만 쓴다(지갑·환율 알림 설계 §4.4).
 *
 * <p>API 키가 필요 없고, 값은 하루 한 번 갱신된다. 과도하게 호출하면 HTTP 429가 오므로 배치가
 * 하루 몇 번만 부른다. 이용 조건상 화면에 출처 표기("Rates By Exchange Rate API")가 필요하다 —
 * 그래서 이 값으로 채운 행은 source=ER_API로 저장해 앱이 출처를 구분할 수 있게 한다.
 *
 * <p>@Component: 스프링 빈으로 등록한다. 생성자의 RestClient.Builder는 스프링 부트가 자동으로
 * 만들어 주입한다(KoreaEximClient·GooglePlacesClient와 같은 방식).
 *
 * <p>재시도는 하지 않는다. 배치가 하루 세 번 돌기 때문에 한 번 실패해도 다음 실행에서 다시 받는다.
 * 실패는 {@link ExternalApiException}으로 통일해 던지고, 호출부(배치)가 잡아 기존 캐시를 유지한다.
 */
@Component
public class OpenErApiClient {

    private final RestClient restClient;

    public OpenErApiClient(RestClient.Builder builder) {
        this.restClient = builder.baseUrl("https://open.er-api.com").build();
    }

    public OpenErApiResponse fetchKrwBase() {
        OpenErApiResponse body;
        try {
            body = restClient.get()
                    .uri("/v6/latest/KRW")
                    .retrieve()
                    .body(OpenErApiResponse.class);
        } catch (RestClientException e) {
            // 4xx/5xx 응답, 연결 실패, 타임아웃, JSON 변환 실패가 모두 RestClientException 계열이다.
            throw new ExternalApiException("open.er-api.com 호출 실패", e);
        }
        if (body == null || !"success".equals(body.result()) || body.rates() == null) {
            throw new ExternalApiException("open.er-api.com 응답이 성공이 아님: "
                    + (body == null ? "본문 없음" : body.result()));
        }
        return body;
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.OpenErApiClientTest'`
Expected: PASS (3개)

- [ ] **Step 6: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiResponse.java \
  server/src/main/java/com/travelfootsteps/exchangerate/OpenErApiClient.java \
  server/src/test/java/com/travelfootsteps/exchangerate/OpenErApiClientTest.java
git commit -m "feat(server): 수출입은행 미지원 통화용 open.er-api.com 클라이언트 추가"
```

---

### Task 3: 배치 재작성 — 11시 이후 실행, 두 소스, 기동 시 보정

**Files:**
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java` (전체 교체)
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateRepository.java`
- Create: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateStartupBackfill.java`
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximClient.java` (`fetchTodayRates()` 삭제)
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximApiItem.java` (주석)
- Test: `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateBatchSchedulerTest.java` (전체 교체)

**Interfaces:**
- Consumes: Task 1의 `ExchangeRate.of(...)`, `apply(...)`, `getSource()`, `getPreviousKrwRate()`, `RateSource`; Task 2의 `OpenErApiClient.fetchKrwBase()`, `OpenErApiResponse`; 기존 `KoreaEximClient.fetchRates(LocalDate)`, `KoreaEximApiItem(int result, String currencyUnit, String dealBaseRate)`, `CountryRepository.findAll()`, `Country.getCurrencyCode()`
- Produces:
  - `ExchangeRateBatchScheduler(KoreaEximClient eximClient, OpenErApiClient erApiClient, ExchangeRateRepository repository, CountryRepository countryRepository)`
  - `void runScheduled()` (cron `0 5 11,12,15 * * *`, KST)
  - `void refresh(LocalDate today)`
  - `void backfillIfNeeded(LocalDate today)`
  - `void backfill(LocalDate today)`
  - `static final ZoneId ExchangeRateBatchScheduler.KST`, `static final int BACKFILL_MAX_DAYS = 10`
  - `boolean ExchangeRateRepository.existsBySourceAndPreviousKrwRateIsNull(RateSource source)`

- [ ] **Step 1: 실패하는 배치 테스트 작성 (전체 교체)**

`server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateBatchSchedulerTest.java`:

```java
package com.travelfootsteps.exchangerate;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.externaldata.ExternalApiException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
// 저장소 스텁을 setUp에서 한꺼번에 깔아 두는데, 모든 테스트가 그 스텁을 다 쓰지는 않는다.
@MockitoSettings(strictness = Strictness.LENIENT)
class ExchangeRateBatchSchedulerTest {

    static final LocalDate D6 = LocalDate.of(2026, 10, 6);
    static final LocalDate D7 = LocalDate.of(2026, 10, 7);
    static final LocalDate D8 = LocalDate.of(2026, 10, 8);
    static final LocalDate D9 = LocalDate.of(2026, 10, 9); // 한글날(공휴일)
    // 2026-10-09 00:02:31 UTC = 2026-10-09 09:02:31 KST
    static final long ER_UPDATED_UNIX = 1791504151L;
    // 2026-10-08 15:30:00 UTC = 2026-10-09 00:30:00 KST (UTC 날짜와 KST 날짜가 다른 시각)
    static final long ER_UPDATED_UNIX_UTC_PREV_DAY = 1791473400L;

    @Mock KoreaEximClient eximClient;
    @Mock OpenErApiClient erApiClient;
    @Mock ExchangeRateRepository repository;
    @Mock CountryRepository countryRepository;

    // 저장소 목을 메모리 맵처럼 동작시킨다 — save한 엔티티를 findByCurrencyCode로 다시 꺼낼 수 있어야
    // apply()가 이전값을 쌓는 과정을 검증할 수 있다.
    final Map<String, ExchangeRate> stored = new HashMap<>();
    ExchangeRateBatchScheduler scheduler;

    @BeforeEach
    void setUp() {
        when(repository.findByCurrencyCode(anyString()))
                .thenAnswer(inv -> Optional.ofNullable(stored.get(inv.getArgument(0, String.class))));
        when(repository.save(any(ExchangeRate.class))).thenAnswer(inv -> {
            ExchangeRate rate = inv.getArgument(0);
            stored.put(rate.getCurrencyCode(), rate);
            return rate;
        });
        when(repository.findAll()).thenAnswer(inv -> new ArrayList<>(stored.values()));
        when(repository.count()).thenAnswer(inv -> (long) stored.size());
        when(repository.existsBySourceAndPreviousKrwRateIsNull(any())).thenAnswer(inv ->
                stored.values().stream().anyMatch(r ->
                        r.getSource() == inv.getArgument(0) && r.getPreviousKrwRate() == null));
        countries("USD", "JPY", "VND");
        scheduler = new ExchangeRateBatchScheduler(eximClient, erApiClient, repository, countryRepository);
    }

    void countries(String... currencyCodes) {
        List<Country> list = Arrays.stream(currencyCodes).map(code -> {
            Country country = mock(Country.class);
            when(country.getCurrencyCode()).thenReturn(code);
            return country;
        }).toList();
        when(countryRepository.findAll()).thenReturn(list);
    }

    static OpenErApiResponse erRates(long updatedUnix, String... codeAndRate) {
        Map<String, BigDecimal> rates = new LinkedHashMap<>();
        for (int i = 0; i < codeAndRate.length; i += 2) {
            rates.put(codeAndRate[i], new BigDecimal(codeAndRate[i + 1]));
        }
        return new OpenErApiResponse("success", updatedUnix, rates);
    }

    @Test
    void 수출입은행_값을_1단위_원화로_정규화해_저장하고_KRW는_저장하지_않는다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(
                new KoreaEximApiItem(1, "USD", "1,339.2"),
                new KoreaEximApiItem(1, "JPY(100)", "847.46"),
                new KoreaEximApiItem(1, "KRW", "1")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(stored.get("USD").getBaseDate()).isEqualTo(D8);
        assertThat(stored.get("USD").getSource()).isEqualTo(RateSource.EXIM);
        assertThat(stored.get("JPY").getKrwRate()).isEqualByComparingTo("8.4746");
        assertThat(stored).doesNotContainKey("KRW");
    }

    @Test
    void result가_1이_아닌_항목은_건너뛴다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(4, null, null)));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored).doesNotContainKeys("USD", "JPY");
    }

    @Test
    void 수출입은행에_없는_통화만_참고환율로_채운다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(erApiClient.fetchKrwBase())
                .thenReturn(erRates(ER_UPDATED_UNIX, "USD", "0.000745", "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored.get("USD").getSource()).isEqualTo(RateSource.EXIM);
        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
        assertThat(stored.get("VND").getKrwRate()).isEqualByComparingTo("0.051934");
        assertThat(stored.get("VND").getBaseDate()).isEqualTo(D9);
    }

    @Test
    void 공휴일에_수출입은행이_빈_배열이면_기존_수출입은행_통화를_참고환율로_덮지_않는다() {
        stored.put("USD", ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM));
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(erApiClient.fetchKrwBase())
                .thenReturn(erRates(ER_UPDATED_UNIX, "USD", "0.000745", "VND", "19.255146"));

        scheduler.refresh(D9);

        assertThat(stored.get("USD").getSource()).isEqualTo(RateSource.EXIM);
        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(stored.get("USD").getBaseDate()).isEqualTo(D7);
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
    }

    @Test
    void 참고환율_고시일은_UTC가_아니라_KST_날짜다() {
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(erApiClient.fetchKrwBase())
                .thenReturn(erRates(ER_UPDATED_UNIX_UTC_PREV_DAY, "VND", "19.255146"));

        scheduler.refresh(D9);

        assertThat(stored.get("VND").getBaseDate()).isEqualTo(D9);
    }

    @Test
    void 수출입은행_호출이_실패해도_참고환율은_갱신한다() {
        when(eximClient.fetchRates(D8)).thenThrow(new ExternalApiException("장애"));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored.get("VND").getKrwRate()).isEqualByComparingTo("0.051934");
    }

    @Test
    void 참고환율_호출이_실패해도_수출입은행_값은_저장되고_예외를_던지지_않는다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(erApiClient.fetchKrwBase()).thenThrow(new ExternalApiException("장애"));

        scheduler.refresh(D8);

        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(stored).doesNotContainKey("VND");
    }

    @Test
    void 참고환율_대상이_없으면_open_er_api를_호출하지_않는다() {
        countries("USD");
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));

        scheduler.refresh(D8);

        verify(erApiClient, never()).fetchKrwBase();
    }

    @Test
    void 보정_실행은_최근_영업일_2개를_찾아_이전값까지_채운다() {
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(eximClient.fetchRates(D7)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,333.6")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.backfillIfNeeded(D9);

        ExchangeRate usd = stored.get("USD");
        assertThat(usd.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(usd.getBaseDate()).isEqualTo(D8);
        assertThat(usd.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(usd.getPreviousBaseDate()).isEqualTo(D7);
        assertThat(usd.changePercent()).isEqualByComparingTo("0.42");
        verify(eximClient, never()).fetchRates(D6);
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
    }

    @Test
    void 보정_실행은_최대_10일까지만_거슬러_올라간다() {
        when(eximClient.fetchRates(any())).thenReturn(List.of());

        scheduler.backfillIfNeeded(D9);

        verify(eximClient, times(ExchangeRateBatchScheduler.BACKFILL_MAX_DAYS)).fetchRates(any());
    }

    @Test
    void 보정_실행_중_한_날짜_호출이_실패해도_다음_날짜로_넘어간다() {
        when(eximClient.fetchRates(D9)).thenThrow(new ExternalApiException("장애"));
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(eximClient.fetchRates(D7)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,333.6")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.backfillIfNeeded(D9);

        assertThat(stored.get("USD").getPreviousKrwRate()).isEqualByComparingTo("1333.6");
    }

    @Test
    void 수출입은행_행이_모두_이전값을_가지면_보정_실행을_건너뛴다() {
        ExchangeRate usd = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);
        usd.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);
        stored.put("USD", usd);

        scheduler.backfillIfNeeded(D9);

        verify(eximClient, never()).fetchRates(any());
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.ExchangeRateBatchSchedulerTest'`
Expected: FAIL — 컴파일 에러(생성자 인자 개수 불일치, `refresh`/`backfillIfNeeded`/`BACKFILL_MAX_DAYS`/`existsBySourceAndPreviousKrwRateIsNull` 없음)

- [ ] **Step 3: 저장소에 쿼리 메서드 추가**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateRepository.java` 전체:

```java
package com.travelfootsteps.exchangerate;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

// JpaRepository<ExchangeRate, Long>을 상속하면 save/findAll/count 같은 기본 CRUD
// 메서드를 스프링 데이터 JPA가 자동으로 구현해준다. 아래 메서드들은 메서드 이름만으로
// 스프링 데이터 JPA가 SQL을 자동 생성하는 쿼리 메서드다 — 구현체를 직접 작성할 필요가 없다.
public interface ExchangeRateRepository extends JpaRepository<ExchangeRate, Long> {

    // "WHERE currency_code = ?"
    Optional<ExchangeRate> findByCurrencyCode(String currencyCode);

    // "출처가 source이면서 previous_krw_rate가 NULL인 행이 하나라도 있는가?" — exists로 시작하는 쿼리
    // 메서드는 boolean을 돌려준다. 기동 시 보정 실행이 필요한지 판단하는 데 쓴다(설계 §4.4).
    boolean existsBySourceAndPreviousKrwRateIsNull(RateSource source);
}
```

- [ ] **Step 4: 배치 전체 교체**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java`:

```java
package com.travelfootsteps.exchangerate;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;

// 환율 캐시(exchange_rate)를 채우는 배치. 지갑·환율 알림 설계 §4.4.
//
// @Slf4j(Lombok): 이 클래스 전용 로거(log)를 자동 생성한다.
// @Component: 스프링 빈으로 등록한다 — ServerApplication의 @EnableScheduling 덕분에
// @Scheduled 메서드가 정해진 시각에 자동 실행된다(DailyDataCollectionScheduler와 같은 인프라).
// @RequiredArgsConstructor(Lombok): final 필드 네 개를 받는 생성자를 자동 생성하고,
// 스프링이 그 생성자로 각 빈을 주입한다.
//
// 두 소스를 순서대로 적용한다.
// 1) 한국수출입은행(EXIM): 기본 소스. 영업일 11시 전후에 고시하고, 비영업일·11시 이전에는 빈 배열을 준다.
// 2) open.er-api.com(ER_API): 우리 country 테이블의 통화 중 수출입은행이 고시하지 않는 통화만 채운다.
// 두 소스는 서로 독립적으로 실패한다 — 하나가 실패해도 다른 하나는 계속 적용하고, 실패한 쪽은
// 로그만 남긴 채 기존 캐시를 그대로 둔다(degrade 정책).
@Slf4j
@Component
@RequiredArgsConstructor
public class ExchangeRateBatchScheduler {

    static final ZoneId KST = ZoneId.of("Asia/Seoul");

    // 보정 실행 시 오늘부터 며칠 전까지 거슬러 올라갈지. 설·추석 연휴(최대 5~6일)에 주말이 붙어도
    // 영업일 2개를 찾을 수 있는 여유값이다.
    static final int BACKFILL_MAX_DAYS = 10;

    private final KoreaEximClient eximClient;
    private final OpenErApiClient erApiClient;
    private final ExchangeRateRepository repository;
    private final CountryRepository countryRepository;

    /**
     * 영업일 11:05, 12:05, 15:05(KST)에 실행한다. 수출입은행이 11시 전후에 고시하므로 11:05 실행으로
     * 대부분 받고, 고시가 늦어지는 날을 위해 두 번 더 돈다. 같은 날 여러 번 돌아도
     * {@link ExchangeRate#apply}의 "같은 고시일이면 현재값만 교체" 규칙 덕분에 이전값이 망가지지 않는다.
     *
     * <p>@Transactional: 이 메서드 안의 모든 DB 변경을 하나의 트랜잭션으로 묶는다. 이미 있는 행은
     * apply()로 필드만 바꾸는데, 트랜잭션이 커밋될 때 JPA가 바뀐 필드를 감지해 UPDATE 한다.
     * 주의: @Transactional은 스프링이 만든 프록시를 거쳐 호출될 때만 동작한다. 그래서 스케줄러가 부르는
     * 이 메서드에 붙였고, 안에서 refresh()를 직접 부르는 것(같은 객체 안의 호출)은 이 트랜잭션 안에서 실행된다.
     */
    @Scheduled(cron = "0 5 11,12,15 * * *", zone = "Asia/Seoul")
    @Transactional
    public void runScheduled() {
        refresh(LocalDate.now(KST));
    }

    // 오늘 날짜 기준으로 두 소스를 한 번 적용한다. 테스트가 날짜를 고정해서 부를 수 있게 날짜를 인자로 받는다.
    @Transactional
    public void refresh(LocalDate today) {
        Set<String> eximCodes = applyEximItems(fetchExim(today), today);
        applyErApi(eximCodes);
        log.info("환율 갱신 완료: 수출입은행 {}건", eximCodes.size());
    }

    // 캐시가 비어 있거나, 수출입은행 행 중 아직 이전값이 없는 행이 있을 때만 보정 실행을 한다.
    // 기동 시(ExchangeRateStartupBackfill)에 부른다.
    @Transactional
    public void backfillIfNeeded(LocalDate today) {
        boolean needed = repository.count() == 0
                || repository.existsBySourceAndPreviousKrwRateIsNull(RateSource.EXIM);
        if (!needed) {
            log.info("환율 캐시가 이미 채워져 있어 보정 실행을 건너뛴다");
            return;
        }
        backfill(today);
    }

    /**
     * 오늘부터 최대 {@link #BACKFILL_MAX_DAYS}일을 거슬러 올라가며 데이터가 있는 최근 영업일 2개를 찾고,
     * 오래된 날부터 차례로 적용한다. 오래된 날을 먼저 넣어야 apply()의 "더 늦은 고시일이 오면 기존값을
     * 이전값으로 민다" 규칙대로 현재값·이전값이 제자리에 쌓인다. 그래야 서버를 처음 띄운 날부터 전일 대비가 나온다.
     */
    @Transactional
    public void backfill(LocalDate today) {
        Map<LocalDate, List<KoreaEximApiItem>> businessDays = new LinkedHashMap<>();
        for (int i = 0; i < BACKFILL_MAX_DAYS && businessDays.size() < 2; i++) {
            LocalDate date = today.minusDays(i);
            List<KoreaEximApiItem> items = fetchExim(date);
            if (items.stream().anyMatch(this::isUsable)) {
                businessDays.put(date, items);
            }
        }
        List<LocalDate> oldestFirst = new ArrayList<>(businessDays.keySet());
        Collections.reverse(oldestFirst);

        Set<String> eximCodes = new HashSet<>();
        for (LocalDate date : oldestFirst) {
            eximCodes.addAll(applyEximItems(businessDays.get(date), date));
        }
        applyErApi(eximCodes);
        log.info("환율 보정 실행 완료: 영업일 {}개 {}", oldestFirst.size(), oldestFirst);
    }

    // 수출입은행 호출. 재시도(1s/2s/4s)는 KoreaEximClient가 하고, 그래도 실패하면 여기서 빈 목록으로
    // 바꿔 "그날은 데이터 없음"과 같게 취급한다 — 한 날짜의 실패가 배치 전체를 멈추지 않게 한다.
    private List<KoreaEximApiItem> fetchExim(LocalDate date) {
        try {
            return eximClient.fetchRates(date);
        } catch (Exception e) {
            log.error("수출입은행 환율 조회 실패({}) — 이 날짜는 건너뛴다", date, e);
            return List.of();
        }
    }

    // result=1(성공)이고 값이 있으며 원화(KRW) 자신이 아닌 항목만 저장 대상이다.
    private boolean isUsable(KoreaEximApiItem item) {
        return item.result() == 1
                && item.currencyUnit() != null
                && item.dealBaseRate() != null
                && !"KRW".equals(item.normalizedCurrencyCode());
    }

    // 저장한 통화코드 집합을 돌려준다 — ER_API가 "오늘 수출입은행이 준 통화"를 건드리지 않게 하는 데 쓴다.
    private Set<String> applyEximItems(List<KoreaEximApiItem> items, LocalDate baseDate) {
        Set<String> codes = new HashSet<>();
        for (KoreaEximApiItem item : items) {
            if (!isUsable(item)) {
                continue;
            }
            BigDecimal rate = parseRate(item.dealBaseRate());
            if (item.isPerHundredUnits()) {
                // "JPY(100)"은 100엔당 원화다. 소수점을 두 칸 옮겨 1엔당 원화로 바꾼다(나눗셈 오차 없음).
                rate = rate.movePointLeft(2);
            }
            String code = item.normalizedCurrencyCode();
            upsert(code, rate, baseDate, RateSource.EXIM);
            codes.add(code);
        }
        return codes;
    }

    private void applyErApi(Set<String> eximCodesToday) {
        Set<String> targets = erApiTargets(eximCodesToday);
        if (targets.isEmpty()) {
            return;
        }
        try {
            OpenErApiResponse response = erApiClient.fetchKrwBase();
            // 갱신 시각은 UTC 유닉스 초다. 한국 날짜로 바꿔야 수출입은행 고시일과 같은 기준이 된다.
            LocalDate baseDate = Instant.ofEpochSecond(response.timeLastUpdateUnix()).atZone(KST).toLocalDate();
            int updated = 0;
            for (String code : targets) {
                BigDecimal unitsPerKrw = response.rates().get(code);
                if (unitsPerKrw == null || unitsPerKrw.signum() <= 0) {
                    log.warn("open.er-api.com 응답에 {} 환율이 없다", code);
                    continue;
                }
                // rates는 "1원 = 몇 단위"라서 뒤집어야 "1단위 = 몇 원"이 된다.
                BigDecimal krwPerUnit = BigDecimal.ONE.divide(unitsPerKrw, 6, RoundingMode.HALF_UP);
                upsert(code, krwPerUnit, baseDate, RateSource.ER_API);
                updated++;
            }
            log.info("참고환율(open.er-api.com) 갱신: {}건", updated);
        } catch (Exception e) {
            log.error("참고환율 갱신 실패 — 기존 캐시를 유지한다", e);
        }
    }

    // ER_API로 채울 통화 = 우리 country 테이블의 통화 − 오늘 수출입은행이 준 통화 − 이미 수출입은행 값으로
    // 관리되는 통화. 마지막 조건이 없으면, 공휴일(수출입은행이 빈 배열)마다 USD 같은 통화가 참고환율로
    // 덮어써진다.
    private Set<String> erApiTargets(Set<String> eximCodesToday) {
        Set<String> eximManaged = repository.findAll().stream()
                .filter(rate -> rate.getSource() == RateSource.EXIM)
                .map(ExchangeRate::getCurrencyCode)
                .collect(Collectors.toSet());
        return countryRepository.findAll().stream()
                .map(Country::getCurrencyCode)
                .filter(Objects::nonNull)
                .map(String::trim) // CHAR(3) 컬럼이라 공백이 붙어 올 수 있다
                .filter(code -> !code.isEmpty() && !"KRW".equals(code))
                .filter(code -> !eximCodesToday.contains(code) && !eximManaged.contains(code))
                .collect(Collectors.toCollection(TreeSet::new));
    }

    // 통화코드가 이미 캐시에 있으면 그 행에 apply()로 반영하고, 없으면 새로 만든다(upsert).
    // exchange_rate.currency_code에 UNIQUE 제약이 있으므로 통화코드당 캐시 행은 항상 하나다.
    private void upsert(String currencyCode, BigDecimal rate, LocalDate baseDate, RateSource source) {
        repository.findByCurrencyCode(currencyCode)
                .ifPresentOrElse(
                        existing -> existing.apply(rate, baseDate, source),
                        () -> repository.save(ExchangeRate.of(currencyCode, rate, baseDate, source))
                );
    }

    // "1,339.2"처럼 천 단위 구분 콤마가 섞인 문자열을 BigDecimal로 변환한다.
    private BigDecimal parseRate(String raw) {
        return new BigDecimal(raw.replace(",", ""));
    }
}
```

- [ ] **Step 5: 기동 시 보정 러너 작성**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateStartupBackfill.java`:

```java
package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * 서버를 띄울 때 환율 캐시가 비어 있으면 최근 영업일 2개를 거슬러 올라가 채운다(설계 §4.4).
 *
 * <p>왜 필요한가 — 스케줄 배치는 영업일 11:05 이후에만 돈다. 서버를 처음 띄운 날이 주말이거나
 * 11시 이전이면, 다음 영업일 오전까지 환율이 하나도 없어 지갑 배너가 비고 알림도 동작하지 않는다.
 *
 * <p>@Component + ApplicationRunner: 스프링 부트가 기동을 마친 뒤(내장 웹서버가 요청을 받을 수 있게 된 뒤)
 * run()을 자동으로 호출한다. 우리가 직접 부르는 코드는 어디에도 없다.
 * <p>@Profile("!test"): 활성 프로필이 test가 아닐 때만 이 빈을 만든다. @SpringBootTest 테스트가 기동하면서
 * 실제 수출입은행·open.er-api.com을 호출하는 일을 막는다.
 * <p>보정 실행이 실패해도 서버 기동은 계속된다 — 예외를 잡아 로그만 남기고, 다음 스케줄에서 다시 받는다.
 */
@Slf4j
@Component
@Profile("!test")
@RequiredArgsConstructor
public class ExchangeRateStartupBackfill implements ApplicationRunner {

    private final ExchangeRateBatchScheduler scheduler;

    @Override
    public void run(ApplicationArguments args) {
        try {
            scheduler.backfillIfNeeded(LocalDate.now(ExchangeRateBatchScheduler.KST));
        } catch (Exception e) {
            log.error("기동 시 환율 보정 실패 — 다음 스케줄에서 다시 시도한다", e);
        }
    }
}
```

- [ ] **Step 6: `KoreaEximClient`에서 안 쓰게 된 메서드 삭제**

`server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximClient.java`에서 다음 블록을 통째로 지운다(배치는 이제 날짜를 직접 넘겨 `fetchRates(LocalDate)`를 부르며, 인자 없는 `LocalDate.now()`는 KST 기준이 아니다):

```java
    /** 오늘 날짜 기준 환율을 조회한다. 배치 스케줄러가 매일 호출하는 진입점이다. */
    public List<KoreaEximApiItem> fetchTodayRates() {
        return fetchRates(LocalDate.now());
    }

```

- [ ] **Step 7: `KoreaEximApiItem`의 "검증 필요" 주석을 실측 결과로 교체**

`server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximApiItem.java`에서 다음 블록을:

```java
// TODO/NOTE(검증 필요): result/cur_unit/deal_bas_r 필드명과 result=1(성공) 코드 의미는
// 공개 문서·자료를 근거로 한 추정이며, 실제 KOREA_EXIM_API_KEY로 라이브 호출해 확인한 적은
// 없다(Task 9 작업 시점에 유효한 키가 없었음). 실제 키가 생기면 한 번 호출해 이 필드명과
// result 코드 의미(특히 인증키 오류/한도 초과 시의 응답 형태)를 확인하고 이 주석을 지울 것.
```

다음으로 바꾼다:

```java
// 실측 확인(2026-10-08, 실제 KOREA_EXIM_API_KEY로 호출): 필드명 result/cur_unit/deal_bas_r이 맞고,
// 정상 항목은 result=1이다. deal_bas_r은 "1,339.2"처럼 천 단위 콤마가 섞인 문자열이다. 응답에는 KRW
// 항목도 들어 있다. 비영업일이나 영업일 11시 이전에는 항목 없이 빈 배열 []이 온다(2026-10-09 한글날 실측).
```

- [ ] **Step 8: 테스트 통과 확인**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.ExchangeRateBatchSchedulerTest' --tests 'com.travelfootsteps.exchangerate.ExchangeRateTest' --tests 'com.travelfootsteps.exchangerate.OpenErApiClientTest'`
Expected: PASS (배치 12개, 엔티티 7개, 클라이언트 3개)

Run: `./gradlew compileJava compileTestJava`
Expected: BUILD SUCCESSFUL (`fetchTodayRates` 삭제로 다른 곳이 깨지지 않았는지 확인)

- [ ] **Step 9: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateBatchScheduler.java \
  server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateRepository.java \
  server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateStartupBackfill.java \
  server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximClient.java \
  server/src/main/java/com/travelfootsteps/exchangerate/KoreaEximApiItem.java \
  server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateBatchSchedulerTest.java
git commit -m "fix(server): 환율 배치를 고시 이후로 옮기고 미지원 통화·기동 시 보정을 추가한다"
```

---

### Task 4: 응답 필드 확장 + 로그인 없이 환율 조회

**Files:**
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateResponse.java` (전체 교체)
- Modify: `server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateController.java` (클래스 주석)
- Modify: `server/src/main/java/com/travelfootsteps/auth/SecurityConfig.java`
- Test: `server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateControllerTest.java`

**Interfaces:**
- Consumes: Task 1의 `ExchangeRate` 게터, `changePercent()`, `RateSource`
- Produces: `GET /api/exchange-rates/{currencyCode}` 응답 JSON
  `{"currencyCode":"JPY","krwRate":8.4746,"baseDate":"2026-10-08","previousKrwRate":8.4,"previousBaseDate":"2026-10-07","changePercent":0.89,"source":"EXIM"}` — 토큰 없이 200. 2·3단계 앱 계획서가 이 계약을 쓴다.

- [ ] **Step 1: 실패하는 컨트롤러 테스트로 수정**

`server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateControllerTest.java`에서

(a) import에 다음 한 줄을 추가한다(`RateSource`는 같은 패키지라 import가 필요 없다):

```java
import static org.hamcrest.Matchers.nullValue;
```

(b) 기존 테스트 `토큰_없이_요청하면_401`을 통째로 지우고, 클래스 끝(마지막 `}` 앞)에 다음 테스트들을 추가한다:

```java
    @Test
    void 이전값과_등락률_출처를_함께_반환한다() throws Exception {
        ExchangeRate jpy = ExchangeRate.of("JPY", new BigDecimal("8.4"), LocalDate.of(2026, 10, 7), RateSource.EXIM);
        jpy.apply(new BigDecimal("8.4746"), LocalDate.of(2026, 10, 8), RateSource.EXIM);
        repository.save(jpy);

        mockMvc.perform(get("/api/exchange-rates/JPY").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.krwRate").value(8.4746))
                .andExpect(jsonPath("$.baseDate").value("2026-10-08"))
                .andExpect(jsonPath("$.previousKrwRate").value(8.4))
                .andExpect(jsonPath("$.previousBaseDate").value("2026-10-07"))
                .andExpect(jsonPath("$.changePercent").value(0.89))
                .andExpect(jsonPath("$.source").value("EXIM"));
    }

    @Test
    void 이전값이_없으면_등락_필드는_null이다() throws Exception {
        repository.save(ExchangeRate.of("GBP", new BigDecimal("1790.12"), LocalDate.of(2026, 10, 8)));

        mockMvc.perform(get("/api/exchange-rates/GBP").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.previousKrwRate").value(nullValue()))
                .andExpect(jsonPath("$.previousBaseDate").value(nullValue()))
                .andExpect(jsonPath("$.changePercent").value(nullValue()));
    }

    @Test
    void 참고환율은_출처가_ER_API로_나간다() throws Exception {
        repository.save(ExchangeRate.of("TWD", new BigDecimal("41.970956"), LocalDate.of(2026, 10, 9), RateSource.ER_API));

        mockMvc.perform(get("/api/exchange-rates/TWD").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.krwRate").value(41.970956))
                .andExpect(jsonPath("$.source").value("ER_API"));
    }

    @Test
    void 토큰_없이도_환율을_조회할_수_있다() throws Exception {
        repository.save(ExchangeRate.of("EUR", new BigDecimal("1500.04"), LocalDate.of(2026, 10, 8)));

        mockMvc.perform(get("/api/exchange-rates/EUR"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currencyCode").value("EUR"));
    }

    @Test
    void 환율이_아닌_다른_API는_여전히_토큰이_필요하다() throws Exception {
        mockMvc.perform(get("/api/countries/JP"))
                .andExpect(status().isUnauthorized());
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인 (Docker 필요)**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.ExchangeRateControllerTest'`
Expected: FAIL — `이전값과_등락률_출처를_함께_반환한다`에서 `No value at JSON path "$.previousKrwRate"`, `토큰_없이도_환율을_조회할_수_있다`에서 `Status expected:<200> but was:<401>`
(Docker가 꺼져 있으면 `Could not find a valid Docker environment`로 전 테스트가 실패한다. Docker Desktop을 켜고 다시 실행한다. Docker를 쓸 수 없는 환경이면 Step 3~5를 진행한 뒤 Step 6을 CI 결과로 확인한다.)

- [ ] **Step 3: 응답 레코드 전체 교체**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateResponse.java`:

```java
package com.travelfootsteps.exchangerate;

import java.math.BigDecimal;
import java.time.LocalDate;

// 조회 API(GET /api/exchange-rates/{currencyCode})의 응답 바디. 컨트롤러가 이 레코드를 반환하면
// 스프링(Jackson)이 필드 이름 그대로 JSON으로 직렬화한다.
// 앞의 세 필드 {currencyCode, krwRate, baseDate}는 Plan B와의 기존 계약이라 그대로 두고, 지갑·환율 알림
// 설계 §4.5의 네 필드를 뒤에 덧붙였다 — 필드를 "추가"만 했으므로 기존 클라이언트는 깨지지 않는다.
// - previousKrwRate/previousBaseDate: 직전 고시일 값. 아직 하루치만 받았으면 null.
// - changePercent: 전 영업일 대비 등락률(%), 소수 둘째 자리. 이전값이 없으면 null.
// - source: "EXIM"(한국수출입은행) 또는 "ER_API"(참고환율). 앱이 출처 표기를 고르는 데 쓴다.
public record ExchangeRateResponse(
        String currencyCode,
        BigDecimal krwRate,
        LocalDate baseDate,
        BigDecimal previousKrwRate,
        LocalDate previousBaseDate,
        BigDecimal changePercent,
        String source
) {
    public static ExchangeRateResponse from(ExchangeRate rate) {
        return new ExchangeRateResponse(
                rate.getCurrencyCode().trim(), // CHAR(3) 컬럼이라 공백이 붙어 올 수 있다
                rate.getKrwRate(),
                rate.getBaseDate(),
                rate.getPreviousKrwRate(),
                rate.getPreviousBaseDate(),
                rate.changePercent(),
                rate.getSource().name());
    }
}
```

- [ ] **Step 4: 보안 설정에 환율 조회 허용 추가**

`server/src/main/java/com/travelfootsteps/auth/SecurityConfig.java`

(a) import 목록에 추가한다:

```java
import org.springframework.http.HttpMethod;
```

(b) 다음 줄을:

```java
                        .requestMatchers("/api/health").permitAll()   // 헬스체크는 로그인 없이 허용
```

다음으로 바꾼다:

```java
                        .requestMatchers("/api/health").permitAll()   // 헬스체크는 로그인 없이 허용
                        // 환율 조회는 로그인 없이 허용한다(지갑·환율 알림 설계 §4.5). 앱의 백그라운드 알림 작업
                        // (WorkManager)은 화면 없이 도는 별도 실행 환경이라 로그인 토큰을 붙일 수 없다. 이 API는
                        // 배치가 미리 채운 공공 환율 캐시를 DB에서 읽기만 하므로 외부 API 비용이 생기지 않는다.
                        // HttpMethod.GET으로 조회만 열었고, 순서상 아래 "/api/**" 규칙보다 먼저 와야 먼저 매칭된다.
                        .requestMatchers(HttpMethod.GET, "/api/exchange-rates/**").permitAll()
```

- [ ] **Step 5: 컨트롤러 주석을 실제 동작에 맞게 수정**

`server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateController.java`에서 다음 블록을:

```java
// @RestController + @RequestMapping("/api/exchange-rates"): 이 클래스의 메서드들이 HTTP
// 요청을 처리하고 반환값을 JSON으로 직렬화해 응답 바디에 담는다. SecurityConfig의
// "/api/**".authenticated() 규칙에 걸리므로, 이 엔드포인트도 다른 /api/** 와 마찬가지로
// Authorization 헤더의 Firebase ID 토큰이 있어야 접근할 수 있다.
```

다음으로 바꾼다:

```java
// @RestController + @RequestMapping("/api/exchange-rates"): 이 클래스의 메서드들이 HTTP
// 요청을 처리하고 반환값을 JSON으로 직렬화해 응답 바디에 담는다. 다른 /api/**와 달리 이 GET 조회는
// SecurityConfig에서 permitAll로 열려 있어 토큰 없이도 호출된다 — 앱의 백그라운드 알림 작업에는
// 로그인 토큰이 없기 때문이다(지갑·환율 알림 설계 §4.5). 토큰을 붙여 호출해도 똑같이 동작한다.
```

- [ ] **Step 6: 테스트 통과 확인 (Docker 필요)**

Run: `./gradlew test --tests 'com.travelfootsteps.exchangerate.*'`
Expected: PASS (컨트롤러 테스트는 기존 3개 + 새 5개 = 8개. `ddl-auto=validate`가 V10 마이그레이션과 엔티티 매핑이 일치하는지도 이때 함께 검증한다)

- [ ] **Step 7: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateResponse.java \
  server/src/main/java/com/travelfootsteps/exchangerate/ExchangeRateController.java \
  server/src/main/java/com/travelfootsteps/auth/SecurityConfig.java \
  server/src/test/java/com/travelfootsteps/exchangerate/ExchangeRateControllerTest.java
git commit -m "feat(server): 환율 응답에 전 영업일 대비 등락과 출처를 담고 로그인 없이 조회를 허용한다"
```

---

### Task 5: 실제 API로 끝까지 확인

코드 변경은 없다. 실제 키와 실제 DB로 1단계가 동작하는지 확인한다.

**Files:** 없음

- [ ] **Step 1: 서버 전체 테스트 (Docker 필요)**

Run: `./gradlew test`
Expected: BUILD SUCCESSFUL. Docker를 쓸 수 없으면 `./gradlew test --tests 'com.travelfootsteps.exchangerate.ExchangeRateTest' --tests 'com.travelfootsteps.exchangerate.OpenErApiClientTest' --tests 'com.travelfootsteps.exchangerate.ExchangeRateBatchSchedulerTest'`만 돌리고, 나머지는 PR의 CI(`Spring Boot` 체크)로 확인한다.

- [ ] **Step 2: 서버 기동 후 보정 실행 로그 확인**

Run: `./gradlew bootRun --args='--spring.profiles.active=dev'`
Expected: 로그에 `환율 보정 실행 완료: 영업일 2개 [...]`와 `참고환율(open.er-api.com) 갱신: N건`이 찍힌다. Flyway가 `V10__exchange_rate_previous` 마이그레이션을 적용했다는 로그도 보인다.

- [ ] **Step 3: DB에서 값 확인**

Run (`server/.env`의 `DB_PASSWORD` 사용):

```bash
PGPASSWORD=<DB_PASSWORD> psql -U postgres -h localhost -d travelfootsteps -c "SELECT currency_code, krw_rate, base_date, previous_krw_rate, previous_base_date, source FROM exchange_rate ORDER BY source, currency_code;"
```

Expected:
- `EXIM` 행 약 22개(USD, JPY, EUR, CNH 등). 모두 `previous_krw_rate`가 채워져 있다. JPY는 약 8.4대(1엔 기준).
- `ER_API` 행 6개: `CNY`, `CZK`, `PHP`, `TRY`, `TWD`, `VND`. 첫날은 `previous_krw_rate`가 비어 있다(다음 날 배치부터 채워진다).
- `KRW` 행은 없다.

- [ ] **Step 4: 토큰 없이 API 호출**

Run:

```bash
curl -s http://localhost:8080/api/exchange-rates/JPY
curl -s http://localhost:8080/api/exchange-rates/VND
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/countries/JP
```

Expected:
- JPY: `{"currencyCode":"JPY","krwRate":...,"baseDate":"...","previousKrwRate":...,"previousBaseDate":"...","changePercent":...,"source":"EXIM"}`
- VND: `"source":"ER_API"`, `krwRate` 약 0.05
- 국가 조회는 `401`

- [ ] **Step 5: 서버 종료**

`bootRun` 터미널에서 Ctrl+C. 종료되지 않고 8080이 남아 있으면 해당 Java 프로세스를 종료한다(`Get-NetTCPConnection -LocalPort 8080`으로 PID 확인).

---

## Self-Review

- **Spec §4.1 문제 5가지**: 07:00 배치 → Task 3 cron `0 5 11,12,15`. 공휴일 `[]` → Task 3 `applyEximItems`가 빈 목록이면 아무것도 안 함 + `공휴일에_…` 테스트. 이전값 없음 → Task 1 `previous_*` + `apply()`. 정밀도 → Task 1 V10. CNH/CNY → Task 3 ER_API 대상 선별(CNY는 수출입은행 응답에 없으므로 ER_API로 채워짐).
- **§4.3 갱신 규칙 3분기**: Task 1 테스트 3개.
- **§4.4 배치**: 스케줄·기동 시 보정(Task 3 Step 5)·10일 거슬러 올라가기·KST 날짜·독립 실패 모두 Task 3 테스트에 있음.
- **§4.5 API·보안**: Task 4.
- **§4.6 테스트 목록**: 엔티티(Task 1), 배치(Task 3), 컨트롤러·보안(Task 4) 모두 대응.
- **타입 일관성**: `RateSource`, `apply(BigDecimal, LocalDate, RateSource)`, `fetchKrwBase()`, `existsBySourceAndPreviousKrwRateIsNull(RateSource)`, `BACKFILL_MAX_DAYS`, `KST`가 정의한 태스크와 쓰는 태스크에서 같은 이름이다.
