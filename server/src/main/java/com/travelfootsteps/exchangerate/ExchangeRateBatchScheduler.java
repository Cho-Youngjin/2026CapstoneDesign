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

    // 수출입은행 행이 하나도 없거나(캐시가 비었거나 참고환율 행만 있는 경우), 수출입은행 행 중 아직
    // 이전값이 없는 행이 있을 때만 보정 실행을 한다. 기동 시(ExchangeRateStartupBackfill)에 부른다.
    @Transactional
    public void backfillIfNeeded(LocalDate today) {
        boolean needed = !repository.existsBySource(RateSource.EXIM)
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
