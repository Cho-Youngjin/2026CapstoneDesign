package com.travelfootsteps.embassy;

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

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

/**
 * EmbassyCollector의 통합 테스트.
 *
 * <p>VisaRequirementCollectorTest(Task 3)/TravelAlertCollectorTest(Task 4)와 동일한 패턴을
 * 따른다: Testcontainers로 실제 PostgreSQL에 마이그레이션을 적용해 실제 스키마·제약조건을
 * 검증하되, 외교부 API 호출({@link EmbassyClient})은 {@code @MockitoBean}으로 대체해서
 * 네트워크에 의존하지 않는다.
 *
 * <p>이 테스트가 검증하는 것: (1) 실제 API 필드명(embassy_kor_nm/embassy_lat 등)으로 받은
 * 값이 Embassy 엔티티에 그대로 반영되는지, (2) {@link EmbassyClient#fetch}가 재시도를 다
 * 소진하고 {@link ExternalApiException}을 던졌을 때 {@link EmbassyCollector#collectOne}이
 * 그 예외를 삼키고 조용히 반환하며, 그 국가의 기존 행은 지워지지 않고 그대로 남는지 여부 —
 * 이 보장은 DailyDataCollectionSchedulerTest처럼 수집기 자체를 목으로 대체하는 테스트로는
 * 검증할 수 없다.
 */
@SpringBootTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(EmbassyCollectorTest.TestBeans.class)
class EmbassyCollectorTest {

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
    EmbassyRepository embassyRepository;
    @Autowired
    EmbassyCollector collector;

    // EmbassyClient 전체를 목으로 교체한다 — 이 테스트가 검증하려는 것은 "API 응답을 받은 뒤
    // DB에 어떻게 반영하는가"이지 실제 외교부 API 호출 자체가 아니다.
    @MockitoBean
    EmbassyClient embassyClient;

    @Test
    void 실제_API_필드명으로_받은_공관_정보를_저장한다() {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        // docs/api-samples/embassy-vn.json의 첫 번째 항목을 그대로 옮긴 값.
        when(embassyClient.fetch("VN")).thenReturn(List.of(new EmbassyApiItem(
                "VN", "대사관", "주 베트남 대한민국 대사관", 21.067095, 105.796723,
                "+84-(0)236-3566-100", "+82-(0)2-3210-0404",
                "Tang 3-4, Lo A1-2 Chuong Duong, P. Khue My, Q. Ngu Hanh Son, TP. Da Nang, Vietnam,  Vietnam")));

        collector.collectOne(vietnam);

        List<Embassy> saved = embassyRepository.findByCountryId(vietnam.getId());
        assertThat(saved).hasSize(1);
        assertThat(saved.get(0).getType()).isEqualTo("대사관");
        assertThat(saved.get(0).getName()).isEqualTo("주 베트남 대한민국 대사관");
        assertThat(saved.get(0).getLat()).isEqualTo(21.067095);
        assertThat(saved.get(0).getLng()).isEqualTo(105.796723);
        assertThat(saved.get(0).getEmergencyPhone()).isEqualTo("+82-(0)2-3210-0404");
    }

    @Test
    void 재시도_소진_예외는_배치를_중단시키지_않고_기존_행을_그대로_둔다() {
        Country japan = countryRepository.findByIsoAlpha2("JP").orElseThrow();
        embassyRepository.save(Embassy.builder()
                .countryId(japan.getId()).type("대사관").name("주일본 대한민국 대사관")
                .lat(35.6762).lng(139.7503).phone("+81-3-0000-0000")
                .emergencyPhone("+81-90-0000-0000").address("Tokyo").build());
        when(embassyClient.fetch("JP")).thenThrow(new ExternalApiException("일시 장애"));

        collector.collectOne(japan); // 예외를 던지지 않아야 한다

        List<Embassy> after = embassyRepository.findByCountryId(japan.getId());
        assertThat(after).hasSize(1); // 기존 행이 지워지지 않고 그대로 남아있다(교체는 fetch 성공 후에만 일어난다)
        assertThat(after.get(0).getName()).isEqualTo("주일본 대한민국 대사관");
    }
}
