package com.travelfootsteps.embassy;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.externaldata.ExternalApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

// @Slf4j / @Component / @RequiredArgsConstructor: TravelAlertCollector와 동일한 역할.
//
// 배치 흐름에서의 위치: DailyDataCollectionScheduler.runDaily() -> collectOne(country) ->
// EmbassyClient.fetch() -> DataGoKrHttpClient.getItems() -> data.go.kr 실제 HTTP 호출.
@Slf4j
@Component
@RequiredArgsConstructor
public class EmbassyCollector {

    private final EmbassyClient client;
    private final EmbassyRepository repository;

    /**
     * 국가 하나의 재외공관 목록을 수집해서 기존 행을 전부 지우고 새로 받아온 것으로 교체한다.
     * TravelAlertCollector와 동일한 이유(국가당 여러 건, upsert 키 애매)로 "교체(replace)"
     * 전략을 쓴다.
     *
     * <p>실패 처리: {@link EmbassyClient#fetch}가 재시도를 다 소진하고
     * {@link ExternalApiException}을 던지면 예외를 잡아 로그만 남기고 조용히 반환한다 —
     * 이때 그 국가의 기존 행은 지워지지 않고 그대로 남는다.
     *
     * @param country 수집 대상 국가 (Phase 0의 country 테이블 행)
     */
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
