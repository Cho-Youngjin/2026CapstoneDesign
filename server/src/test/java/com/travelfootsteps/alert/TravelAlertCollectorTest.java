package com.travelfootsteps.alert;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.externaldata.ExternalApiException;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

/**
 * TravelAlertCollector의 통합 테스트.
 *
 * <p>VisaRequirementCollectorTest(Task 3)와 동일한 패턴을 따른다: Testcontainers로 실제
 * PostgreSQL에 마이그레이션을 적용해 실제 스키마·제약조건을 검증하되, 외교부 API 호출
 * ({@link TravelAlertClient})은 {@code @MockitoBean}으로 대체해서 네트워크에 의존하지 않는다.
 *
 * <p>이 테스트가 검증하는 것: (1) 실제 API에는 없는 title 필드를 국가명+등급으로 직접 조합하는
 * 로직, (2) {@link TravelAlertClient#fetch}가 재시도를 다 소진하고 {@link ExternalApiException}을
 * 던졌을 때 {@link TravelAlertCollector#collectOne}이 그 예외를 삼키고 조용히 반환하며, 그
 * 국가의 기존 행은 지워지지 않고 그대로 남는지 여부 — 이 보장은 DailyDataCollectionSchedulerTest처럼
 * 수집기 자체를 목으로 대체하는 테스트로는 검증할 수 없다.
 */
@SpringBootTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(TravelAlertCollectorTest.TestBeans.class)
class TravelAlertCollectorTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            return new StubTokenVerifier();
        }
    }

    @Autowired
    CountryRepository countryRepository;
    @Autowired
    TravelAlertRepository travelAlertRepository;
    @Autowired
    TravelAlertCollector collector;

    // TravelAlertClient 전체를 목으로 교체한다 — 이 테스트가 검증하려는 것은 "API 응답을 받은 뒤
    // DB에 어떻게 반영하는가"이지 실제 외교부 API 호출 자체가 아니다.
    @MockitoBean
    TravelAlertClient travelAlertClient;

    @Test
    void 수집한_경보의_제목은_국가명과_등급으로_조합해서_저장한다() {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        // 실제 API 응답(docs/api-samples/travel-alarm-vn.json)에는 title 필드가 없다.
        when(travelAlertClient.fetch("VN")).thenReturn(List.of(
                new TravelAlertApiItem("VN", "1", "전 지역", "20260101")));

        collector.collectOne(vietnam);

        List<TravelAlert> saved = travelAlertRepository.findByCountryIdOrderByIssuedAtDesc(vietnam.getId());
        assertThat(saved).hasSize(1);
        assertThat(saved.get(0).getLevel()).isEqualTo(1);
        assertThat(saved.get(0).getRegion()).isEqualTo("전 지역");
        assertThat(saved.get(0).getTitle()).isEqualTo("베트남 여행경보 1단계");
    }

    @Test
    void 재시도_소진_예외는_배치를_중단시키지_않고_기존_행을_그대로_둔다() {
        Country japan = countryRepository.findByIsoAlpha2("JP").orElseThrow();
        travelAlertRepository.save(TravelAlert.builder()
                .countryId(japan.getId()).level(1).region("전역").title("일본 여행경보 1단계")
                .issuedAt(OffsetDateTime.now()).build());
        when(travelAlertClient.fetch("JP")).thenThrow(new ExternalApiException("일시 장애"));

        collector.collectOne(japan); // 예외를 던지지 않아야 한다

        List<TravelAlert> after = travelAlertRepository.findByCountryIdOrderByIssuedAtDesc(japan.getId());
        assertThat(after).hasSize(1); // 기존 행이 지워지지 않고 그대로 남아있다(교체는 fetch 성공 후에만 일어난다)
        assertThat(after.get(0).getTitle()).isEqualTo("일본 여행경보 1단계");
    }
}
