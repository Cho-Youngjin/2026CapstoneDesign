package com.travelfootsteps.footsteps;

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

import static org.assertj.core.api.Assertions.assertThat;
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

        var saved = checkinRepository.findAll();
        assertThat(saved).hasSize(1);
        assertThat(saved.get(0).getFirebaseUid()).isEqualTo("uid-123");
        assertThat(saved.get(0).getCountryId()).isEqualTo(vietnam.getId());
        assertThat(saved.get(0).getSource()).isEqualTo("AUTO");
    }

    @Test
    void 걸음수는_같은_날짜_국가_조합이면_upsert한다() throws Exception {
        String body = """
                [
                  {"localId": 1, "date": "2026-12-20T00:00:00.000Z", "countryIso": "VN", "stepCount": 3000}
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

        var all = dailyStepRepository.findAll();
        assertThat(all).hasSize(1);
        assertThat(all.get(0).getStepCount()).isEqualTo(5000);
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
}
