package com.travelfootsteps.visa;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.externaldata.ExternalApiException;
import com.travelfootsteps.support.StubTokenVerifier;
import jakarta.persistence.EntityManager;
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
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.time.OffsetDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

/**
 * VisaRequirementCollector의 통합 테스트.
 *
 * <p>Testcontainers로 실제 PostgreSQL에 V1/V2 마이그레이션을 적용해 실제 스키마·제약조건을
 * 검증하되, 외교부 API 호출({@link EntranceVisaClient})은 목(mock)으로 대체해서 네트워크에
 * 의존하지 않는다.
 *
 * <p>브리프의 원래 예시 코드는 {@code @TestConfiguration} + {@code @Bean mock(...)}으로
 * {@code EntranceVisaClient}를 교체하려 했는데, 이 방식은 실제 {@code @Component
 * EntranceVisaClient}가 컴포넌트 스캔으로도 등록되어 같은 타입의 빈 정의가 두 개 생겨
 * {@code BeanDefinitionOverrideException}(스프링 부트는 기본적으로 빈 정의 재정의를 금지)이
 * 날 수 있다. 그 대신 스프링 프레임워크 6.2+가 제공하는 {@code @MockitoBean}을 쓴다 —
 * 이 애너테이션은 기존 빈 정의를 안전하게 목으로 교체하도록 설계된 공식 메커니즘이다.
 *
 * <p>또한 {@code @SpringBootTest}는 앱 전체 컨텍스트(SecurityConfig, FirebaseConfig 포함)를
 * 띄우는데, FirebaseConfig/FirebaseTokenVerifier는 진짜 firebase-service-account.json이
 * 있어야만 동작하고 이 저장소에는 그 파일이 없다(비밀정보라 커밋되지 않음, .gitignore 참고).
 * {@code @ActiveProfiles("test")}를 붙이면 두 빈 모두 {@code @Profile("!test")}로 꺼지고,
 * 대신 아래 TestBeans가 등록하는 {@link StubTokenVerifier}가 SecurityConfig가 요구하는
 * {@link TokenVerifier} 빈 자리를 채운다(CountryControllerTest와 동일한 패턴).
 */
// @Transactional(스프링 테스트용): 각 테스트 메서드를 하나의 트랜잭션으로 감싸고, 끝나면
// 자동으로 롤백한다(@DataJpaTest의 기본 동작과 동일한 메커니즘을 여기서는 명시적으로 켠다).
// 두 번째 테스트가 entityManager로 네이티브 UPDATE를 실행하려면 활성 트랜잭션이 필요한데,
// @SpringBootTest는 @DataJpaTest와 달리 트랜잭션을 자동으로 열어주지 않으므로 직접 붙였다.
@SpringBootTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(VisaRequirementCollectorTest.TestBeans.class)
@Transactional
class VisaRequirementCollectorTest {

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
    VisaRequirementRepository visaRequirementRepository;
    @Autowired
    VisaRequirementCollector collector;
    @Autowired
    EntityManager entityManager;

    // EntranceVisaClient 전체를 목으로 교체한다 — 이 테스트가 검증하려는 것은 "API 응답을
    // 받은 뒤 DB에 어떻게 반영하는가"이지 실제 외교부 API 호출 자체가 아니다.
    @MockitoBean
    EntranceVisaClient entranceVisaClient;

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
                "원문", null, null, OffsetDateTime.now());
        visaRequirementRepository.save(verified);
        entityManager.flush();

        // verified 플래그를 세우는 공개 API가 이 계획에는 의도적으로 없다(수기 검증은 운영
        // 프로세스가 맡는다) — 테스트에서만 네이티브 쿼리로 "이미 수기 검증되었다"는 상태를
        // 흉내낸다.
        markVerified(verified.getId());

        when(entranceVisaClient.fetch("JP")).thenReturn(Optional.of(new EntranceVisaApiItem(
                "JP", "일본", "N", "관광 목적 15일 무비자로 변경됨(오수집 가정)", null, null)));

        collector.collectOne(japan);

        VisaRequirement after = visaRequirementRepository.findById(verified.getId()).orElseThrow();
        assertThat(after.getVisaFreeDays()).isEqualTo(90); // 그대로 유지 — 15로 바뀌지 않음
        assertThat(after.isVisaRequired()).isFalse(); // 판정 필드 전부 보존됨
        assertThat(after.isVerified()).isTrue();
        assertThat(after.getRawText()).contains("15일"); // 원문 참고자료는 갱신됨
    }

    @Test
    void 재시도_소진_예외는_배치를_중단시키지_않고_기존_행을_그대로_둔다() {
        Country france = countryRepository.findByIsoAlpha2("FR").orElseThrow();
        when(entranceVisaClient.fetch("FR"))
                .thenThrow(new ExternalApiException("일시 장애"));

        collector.collectOne(france); // 예외를 던지지 않아야 한다

        assertThat(visaRequirementRepository.findByCountryIdAndPassportType(france.getId(), "GENERAL"))
                .isEmpty();
    }

    private void markVerified(Long id) {
        entityManager.createNativeQuery("UPDATE visa_requirement SET verified = true WHERE id = :id")
                .setParameter("id", id)
                .executeUpdate();
        entityManager.clear();
    }
}
