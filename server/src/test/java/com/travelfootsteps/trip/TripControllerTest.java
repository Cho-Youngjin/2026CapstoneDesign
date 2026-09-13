package com.travelfootsteps.trip;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.support.StubTokenVerifier;
import com.travelfootsteps.visa.VisaRequirement;
import com.travelfootsteps.visa.VisaRequirementRepository;
import com.travelfootsteps.visa.VisaRequirementTestFixtures;
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

import java.time.LocalDate;
import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * TripController의 통합 테스트. 특히 2026-09-12 리뷰로 추가된 "판정 스냅샷 고정 + 명시적
 * 새로고침" 설계를 중점적으로 검증한다:
 * <ul>
 *     <li>생성 → 조회 왕복이 (라이브 재계산이 아니라) 저장된 스냅샷을 그대로 돌려주는지</li>
 *     <li>원본 visa_requirement가 바뀌면 judgementStale이 true로 서는지</li>
 *     <li>POST /refresh가 실제로 스냅샷과 준비물을 다시 계산해서 덮어쓰는지</li>
 *     <li>소유자가 아닌 사용자의 요청은 404로 막히는지</li>
 * </ul>
 */
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

    private Country vietnam() {
        return countryRepository.findByIsoAlpha2("VN").orElseThrow();
    }

    /**
     * 베트남의 visa_requirement 행을 원하는 값으로 upsert한다. country_id+passport_type에
     * UNIQUE 제약(V2__visa_requirement.sql)이 있고, 이 테스트 클래스는 @Transactional로 각
     * 테스트를 롤백하지 않는(다른 컨트롤러 테스트들과 동일한 패턴) 방식이라 테스트 메서드 실행
     * 순서와 무관하게 "있으면 갱신, 없으면 생성"으로 동작해야 한다 — 무조건 새로 save()하면
     * 다른 테스트가 먼저 만들어 둔 행과 부딪혀 UNIQUE 제약 위반이 날 수 있다.
     */
    private VisaRequirement upsertVietnamVisaRequirement(boolean visaRequired, Integer visaFreeDays,
                                                          Integer passportValidityMonths, String rawText,
                                                          OffsetDateTime sourceFetchedAt) {
        Long countryId = vietnam().getId();
        VisaRequirement requirement = visaRequirementRepository
                .findByCountryIdAndPassportType(countryId, "GENERAL")
                .orElseGet(() -> VisaRequirement.newUnverified(countryId, "GENERAL"));
        VisaRequirementTestFixtures.applyCollectedData(requirement, visaRequired, visaFreeDays,
                passportValidityMonths, rawText, sourceFetchedAt);
        return visaRequirementRepository.save(requirement);
    }

    /**
     * 베트남을 "무비자 45일, 여권 잔여유효기간 6개월 요건"으로 세팅한다. 이 클래스는
     * @Transactional로 테스트 간 DB를 롤백하지 않으므로(다른 테스트가 VN 요건을 "비자 필요"로
     * 바꿔놓고 끝났을 수 있다), JUnit 5의 기본 실행 순서(선언 순서가 아니다)와 무관하게 항상
     * 이 알려진 상태로 강제 리셋한다 — "없을 때만 만든다"처럼 존재 여부만 보고 건너뛰면 다른
     * 테스트가 남겨둔 상태를 그대로 물려받는 테스트 간 오염이 생길 수 있다.
     */
    private void givenVietnamVisaFree45Days() {
        upsertVietnamVisaRequirement(false, 45, 6, "관광 목적 45일 무비자",
                OffsetDateTime.parse("2026-01-01T00:00:00Z"));
    }

    private Long createTrip(String token, String countryIso2, LocalDate depart, LocalDate ret,
                             LocalDate passportExpiry) throws Exception {
        var request = new CreateTripRequest(countryIso2, depart, ret, passportExpiry);
        String body = mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(body).get("id").asLong();
    }

    @Test
    void 여행_생성시_비자_판정과_역산_일정을_함께_반환한다() throws Exception {
        givenVietnamVisaFree45Days();
        var request = new CreateTripRequest("VN",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2027, 3, 15));

        mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.countryIso2").value("VN"))
                .andExpect(jsonPath("$.visaResult.verdict").value("VISA_FREE_OK"))
                .andExpect(jsonPath("$.visaResult.passportOk").value(false))
                .andExpect(jsonPath("$.judgementStale").value(false))
                .andExpect(jsonPath("$.tasks[?(@.title=='여권 재발급')]").exists())
                .andExpect(jsonPath("$.tasks[?(@.title=='비자 신청')]").doesNotExist());
    }

    @Test
    void 존재하지_않는_국가로_생성하면_404() throws Exception {
        var request = new CreateTripRequest("ZZ",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2027, 3, 15));

        mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isNotFound());
    }

    @Test
    void 다른_사용자의_여행을_조회하면_404() throws Exception {
        givenVietnamVisaFree45Days();
        Long tripId = createTrip("token-a", "VN",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2028, 1, 1));

        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-b"))
                .andExpect(status().isNotFound());
    }

    @Test
    void 다른_사용자의_여행을_새로고침하면_404() throws Exception {
        givenVietnamVisaFree45Days();
        Long tripId = createTrip("token-a", "VN",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2028, 1, 1));

        mockMvc.perform(post("/api/trips/" + tripId + "/refresh").header("Authorization", "Bearer token-b"))
                .andExpect(status().isNotFound());
    }

    @Test
    void 준비물_완료_처리하면_done이_true로_바뀐다() throws Exception {
        givenVietnamVisaFree45Days();
        var request = new CreateTripRequest("VN",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2028, 1, 1));

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

    @Test
    void 조회는_생성_시점의_스냅샷을_그대로_반환하고_원본이_바뀌면_stale_플래그가_선다() throws Exception {
        upsertVietnamVisaRequirement(false, 45, 6, "관광 목적 45일 무비자",
                OffsetDateTime.parse("2026-01-01T00:00:00Z"));

        Long tripId = createTrip("token-a", "VN",
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2028, 1, 1));

        // 생성 직후: 방금 만든 스냅샷과 현재 원본이 같으므로 stale이 아니다.
        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.visaResult.verdict").value("VISA_FREE_OK"))
                .andExpect(jsonPath("$.judgementStale").value(false));

        // 원본 visa_requirement가 이후에 바뀐다(실제로는 배치 재수집이 이렇게 갱신한다) —
        // 무비자 45일 -> 비자 필요로 변경.
        upsertVietnamVisaRequirement(true, 0, null, "비자 필요로 변경됨(재수집 가정)",
                OffsetDateTime.parse("2026-06-01T00:00:00Z"));

        // GET은 여전히 생성 시점의 스냅샷(VISA_FREE_OK)을 그대로 돌려줘야 한다 — 만약 이 값이
        // VISA_REQUIRED로 바뀌어 있다면 GET이 judge()를 라이브로 다시 호출하고 있다는 뜻이므로
        // (금지된) 옛 설계로 되돌아간 버그다. 대신 judgementStale이 true로 서야 한다.
        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.visaResult.verdict").value("VISA_FREE_OK"))
                .andExpect(jsonPath("$.judgementStale").value(true));
    }

    @Test
    void refresh는_판정과_준비물을_새로_계산해서_덮어쓰고_이후_조회에도_반영된다() throws Exception {
        upsertVietnamVisaRequirement(false, 45, 6, "관광 목적 45일 무비자",
                OffsetDateTime.parse("2026-01-01T00:00:00Z"));

        String createdBody = mockMvc.perform(post("/api/trips")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new CreateTripRequest("VN",
                                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), LocalDate.of(2028, 1, 1)))))
                .andReturn().getResponse().getContentAsString();
        JsonNode createdJson = objectMapper.readTree(createdBody);
        Long tripId = createdJson.get("id").asLong();
        // 생성 시점엔 무비자 OK였으므로 "비자 신청" 항목이 없어야 한다.
        assertThat(createdJson.get("tasks").findValuesAsText("title")).doesNotContain("비자 신청");

        // 원본을 "비자 필요"로 바꾼다.
        upsertVietnamVisaRequirement(true, 0, null, "비자 필요로 변경됨(재수집 가정)",
                OffsetDateTime.parse("2026-06-01T00:00:00Z"));

        String refreshedBody = mockMvc.perform(post("/api/trips/" + tripId + "/refresh")
                        .header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.visaResult.verdict").value("VISA_REQUIRED"))
                .andExpect(jsonPath("$.judgementStale").value(false))
                .andReturn().getResponse().getContentAsString();
        JsonNode refreshedJson = objectMapper.readTree(refreshedBody);
        // 새 판정 기준으로 다시 만든 준비물에는 "비자 신청" 항목이 새로 생겨야 한다.
        assertThat(refreshedJson.get("tasks").findValuesAsText("title")).contains("비자 신청");

        // 새로고침도 "다시 스냅샷을 굳히는" 동작이라, 이후 GET은 새로고침된 결과를 그대로
        // 돌려줘야 한다(또 라이브로 재계산하는 게 아니라).
        mockMvc.perform(get("/api/trips/" + tripId).header("Authorization", "Bearer token-a"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.visaResult.verdict").value("VISA_REQUIRED"))
                .andExpect(jsonPath("$.judgementStale").value(false))
                .andExpect(jsonPath("$.tasks[?(@.title=='비자 신청')]").exists());
    }
}
