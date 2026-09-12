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

// @Slf4j(Lombok): 클래스 전용 로거(log)를 자동 생성한다.
// @Component: 스프링 빈으로 등록해서 DailyDataCollectionScheduler가 주입받아 쓸 수 있게 한다.
// @RequiredArgsConstructor(Lombok): final 필드(client/repository)를 받는 생성자를 자동 생성한다.
//
// 배치 흐름에서의 위치: DailyDataCollectionScheduler.runDaily() -> collectOne(country) ->
// TravelAlertClient.fetch() -> DataGoKrHttpClient.getItems() -> data.go.kr 실제 HTTP 호출.
// VisaRequirementCollector(Task 3)와 마찬가지로, 이 메서드가 예외를 삼키고 조용히 반환하므로
// 스케줄러는 국가 하나의 실패로 배치 전체가 죽는 것을 걱정하지 않아도 된다.
@Slf4j
@Component
@RequiredArgsConstructor
public class TravelAlertCollector {

    // 공공API가 issued_at을 "yyyyMMdd" 형식의 문자열로 내려준다(예: "20260101").
    private static final DateTimeFormatter SOURCE_FORMAT = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final TravelAlertClient client;
    private final TravelAlertRepository repository;

    /**
     * 국가 하나의 여행경보를 수집해서 기존 행을 전부 지우고 새로 받아온 것으로 교체한다.
     *
     * <p>여행경보는 비자(VisaRequirement)처럼 국가+여권종류 단일 행이 아니라, 지역별로 여러 건이
     * 동시에 존재할 수 있고 "지금 유효한 경보 목록"만 의미가 있다. upsert 키를 정하기 애매하므로
     * 국가 단위로 기존 행을 지우고(deleteByCountryId) 새로 받아온 항목을 그대로 저장하는
     * "교체(replace)" 전략을 쓴다.
     *
     * <p>실패 처리: {@link TravelAlertClient#fetch}가 재시도를 다 소진하고
     * {@link ExternalApiException}을 던지면, 이 메서드는 예외를 잡아 로그만 남기고 조용히
     * 반환한다 — 이때 그 국가의 기존 행은 지워지지 않고 그대로 남는다(deleteByCountryId는
     * fetch가 성공한 뒤에만 실행되기 때문). 배치가 여러 국가를 순회하는 도중 한 국가의 실패가
     * 전체를 중단시키지 않게 하기 위함이다.
     *
     * @param country 수집 대상 국가 (Phase 0의 country 테이블 행)
     */
    // @Transactional: delete + save 여러 번을 하나의 트랜잭션으로 묶는다. 저장 도중 예외가 나면
    // 전부 롤백되어 "일부만 지워지고 일부만 새로 들어간" 반쪽짜리 상태가 DB에 남지 않는다.
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
            // 파싱 실패를 1단계(안전)로 낙관 처리하면, 실제로는 위험도가 높을 수도 있는 국가를
            // "안전"으로 잘못 보여주게 되는 낙관적 실패(optimistic failure) 버그가 된다.
            // 0(UNKNOWN)으로 남겨 앱이 "확인 필요"로 구분해 표시하게 한다 — 2026-09-12 리뷰 반영.
            return 0; // UNKNOWN
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
