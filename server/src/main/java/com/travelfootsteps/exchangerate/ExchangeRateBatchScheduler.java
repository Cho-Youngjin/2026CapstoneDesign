package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;

// @Slf4j(Lombok): 이 클래스 전용 로거(log)를 자동 생성한다.
// @Component: 스프링 빈으로 등록한다 — ServerApplication의 @EnableScheduling 덕분에
// @Scheduled 메서드가 매일 자동 실행된다(Task 6 DailyDataCollectionScheduler와 동일한 인프라).
// @RequiredArgsConstructor(Lombok): final 필드(client, repository)를 받는 생성자를 자동 생성한다.
@Slf4j
@Component
@RequiredArgsConstructor
public class ExchangeRateBatchScheduler {

    private final KoreaEximClient client;
    private final ExchangeRateRepository repository;

    /**
     * 매일 07:00(KST) — 한국수출입은행이 영업일 고시환율을 발표한 이후 시각.
     *
     * <p>@Transactional: 이 메서드 안의 모든 DB 변경(upsert)을 하나의 트랜잭션으로 묶는다.
     * 배치 도중 예외가 나면(이 메서드 자신이 잡지 않는 한) 이미 반영된 변경까지 통째로
     * 롤백된다 — 하지만 아래처럼 client.fetchTodayRates() 호출과 upsert 루프를 통째로
     * try로 감싸 예외를 여기서 잡아 삼키므로, 실제로는 "부분 갱신 후 예외"가 아니라
     * "API 호출 자체가 실패하면 이번 배치는 아예 아무것도 갱신하지 않는다"는 all-or-nothing
     * 동작이 된다.
     *
     * <p>영업일 주의: 한국수출입은행 API는 주말·공휴일에는 최신 영업일 데이터를 반환하거나
     * 빈 배열을 반환할 수 있다. 그런 날은 items가 비어 있을 뿐 예외가 아니므로, for문이
     * 그냥 0번 돌고 끝난다 — 이전 캐시 값이 계속 유효한 것으로 취급된다는 뜻이다(Global
     * Constraints의 degrade 정책과 동일한 원칙).
     */
    @Scheduled(cron = "0 0 7 * * *", zone = "Asia/Seoul")
    @Transactional
    public void runDaily() {
        try {
            var items = client.fetchTodayRates();
            LocalDate today = LocalDate.now();
            int updated = 0;
            for (KoreaEximApiItem item : items) {
                // result != 1: 인증키 오류, DATA코드 오류, 일일 호출 한도 초과 등 그 항목
                // 자체가 유효한 환율 데이터가 아니라는 뜻이다. 건너뛴다.
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
            // KoreaEximClient가 재시도(1s/2s/4s, 최대 3회)를 다 소진한 뒤에도 실패하면
            // ExternalApiException을 던진다. 여기서 잡아 로그만 남기고 기존 캐시를 그대로
            // 둔다 — 이 배치의 실패가 앱의 다른 기능을 막지 않도록 하는 degrade 정책이다.
            log.error("환율 배치 실패 — 기존 캐시를 유지한다", e);
        }
    }

    // 통화코드가 이미 캐시에 있으면 그 행을 갱신하고, 없으면 새로 만든다(upsert).
    // exchange_rate.currency_code에 UNIQUE 제약이 있으므로 통화코드당 캐시 행은 항상 하나다.
    private void upsert(String currencyCode, BigDecimal rate, LocalDate baseDate) {
        repository.findByCurrencyCode(currencyCode)
                .ifPresentOrElse(
                        existing -> existing.update(rate, baseDate),
                        () -> repository.save(ExchangeRate.of(currencyCode, rate, baseDate))
                );
    }

    // "1,320.50"처럼 천 단위 구분 콤마가 섞인 문자열을 BigDecimal로 변환한다.
    private BigDecimal parseRate(String raw) {
        return new BigDecimal(raw.replace(",", ""));
    }
}
