package com.travelfootsteps.footsteps;

import com.jayway.jsonpath.JsonPath;
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

import java.time.Instant;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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
            stub.register("other-user-token", "uid-456");
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

        // 이 테스트 클래스는 (다른 컨트롤러 테스트들과 동일한 패턴으로) 테스트 간 DB를 롤백하지
        // 않으므로, checkin 테이블 전체 크기가 아니라 이 테스트가 보낸 recordedAt으로 정확히
        // 좁혀서 조회해야 다른 테스트가 만든 행과 섞이지 않는다.
        var saved = checkinRepository.findByFirebaseUidAndRecordedAt("uid-123",
                Instant.parse("2026-12-20T09:00:00.000Z")).orElseThrow();
        assertThat(saved.getCountryId()).isEqualTo(vietnam.getId());
        assertThat(saved.getSource()).isEqualTo("AUTO");
    }

    @Test
    void 걸음수는_같은_날짜_국가_조합이면_upsert한다() throws Exception {
        // date는 순수 로컬 달력 날짜(yyyy-MM-dd)로 보낸다 — 시각/타임존 포함 문자열이 아니다
        // (DailyStepSyncRequest.date 문서 참고). 예전에는 UTC 순간 문자열을 보내도 Jackson이
        // 자정으로 조용히 잘라내 우연히 통과했었는데, 그 문구는 실제 계약과 다르므로 고쳤다.
        String body = """
                [
                  {"localId": 1, "date": "2026-12-20", "countryIso": "VN", "stepCount": 3000}
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

        // 이 테스트 클래스는 테스트 간 DB를 롤백하지 않으므로, daily_steps 테이블 전체 크기가
        // 아니라 (uid, date, country) 키로 정확히 좁혀서 이 upsert가 실제로 갱신했는지 확인한다.
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        var updated = dailyStepRepository
                .findByFirebaseUidAndDateAndCountryId("uid-123", LocalDate.of(2026, 12, 20), vietnam.getId())
                .orElseThrow();
        assertThat(updated.getStepCount()).isEqualTo(5000);
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

    // ─── 복원 조회(GET) — countryIso 노출 / countryId 비노출 ──────────────────────────

    @Test
    void 체크인_복원_조회는_countryIso를_내려주고_countryId는_전혀_노출하지_않는다() throws Exception {
        mockMvc.perform(post("/api/checkins")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content("""
                                [{"localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
                                  "recordedAt": "2026-12-20T09:15:00.000Z", "source": "AUTO"}]
                                """))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/checkins").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].countryIso").value("VN"))
                .andExpect(jsonPath("$[0].countryId").doesNotExist());
    }

    @Test
    void 걸음수_복원_조회는_countryIso를_내려주고_countryId는_전혀_노출하지_않는다() throws Exception {
        // 다른 테스트(걸음수_upsert 테스트)가 (uid-123, 2026-12-20, VN) 키를 이미 쓰고 있으므로
        // (이 클래스는 테스트 간 DB를 롤백하지 않는다) upsert로 그 행과 부딪히지 않도록 날짜를
        // 다르게 잡는다.
        mockMvc.perform(post("/api/daily-steps")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content("""
                                [{"localId": 1, "date": "2026-11-01", "countryIso": "VN", "stepCount": 3000}]
                                """))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/daily-steps").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].countryIso").value("VN"))
                .andExpect(jsonPath("$[0].countryId").doesNotExist());
    }

    // ─── 사용자별 소유권 분리 ───────────────────────────────────────────────────────

    @Test
    void 체크인과_걸음수_복원_조회는_다른_사용자의_행을_보여주지_않는다() throws Exception {
        mockMvc.perform(post("/api/checkins")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content("""
                                [{"localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
                                  "recordedAt": "2026-12-20T10:00:00.000Z", "source": "AUTO"}]
                                """))
                .andExpect(status().isOk());
        mockMvc.perform(post("/api/daily-steps")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content("""
                                [{"localId": 1, "date": "2026-12-22", "countryIso": "VN", "stepCount": 1234}]
                                """))
                .andExpect(status().isOk());

        // 다른 사용자(uid-456)는 자기 자신의 행이 하나도 없으므로 빈 목록을 봐야 한다 —
        // uid-123이 방금 만든 위 두 행이 섞여 보이면 소유권 스코핑 버그다.
        mockMvc.perform(get("/api/checkins").header("Authorization", "Bearer other-user-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
        mockMvc.perform(get("/api/daily-steps").header("Authorization", "Bearer other-user-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    // ─── 체크인 멱등성(재전송 시 중복 생성 방지) ────────────────────────────────────

    @Test
    void 같은_체크인을_두_번_전송해도_한_행만_생기고_같은_serverId를_반환한다() throws Exception {
        String body = """
                [{"localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
                  "recordedAt": "2026-12-25T09:00:00.000Z", "source": "AUTO"}]
                """;

        String firstResponse = mockMvc.perform(post("/api/checkins")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content(body))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        String firstServerId = JsonPath.read(firstResponse, "$[0].serverId");

        String secondResponse = mockMvc.perform(post("/api/checkins")
                        .header("Authorization", "Bearer valid-token")
                        .contentType("application/json")
                        .content(body))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        String secondServerId = JsonPath.read(secondResponse, "$[0].serverId");

        assertThat(secondServerId).isEqualTo(firstServerId);
        // 이 테스트 클래스는 (다른 컨트롤러 테스트들과 동일한 패턴으로) 테스트 간 DB를 롤백하지
        // 않으므로, uid-123 전체 행 수로 세면 다른 테스트가 만든 행까지 섞여 오탐이 날 수 있다.
        // 그래서 이 테스트만의 recordedAt으로 정확히 좁혀서 정확히 한 행만 있는지 확인한다.
        long matchingRows = checkinRepository.findByFirebaseUid("uid-123").stream()
                .filter(c -> c.getRecordedAt().equals(Instant.parse("2026-12-25T09:00:00.000Z")))
                .count();
        assertThat(matchingRows).isEqualTo(1);
    }
}
