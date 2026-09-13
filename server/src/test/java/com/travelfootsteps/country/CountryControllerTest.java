package com.travelfootsteps.country;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(CountryControllerTest.TestBeans.class)
class CountryControllerTest {

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

    @Autowired
    MockMvc mockMvc;

    @Test
    void without_token_returns_401() throws Exception {
        mockMvc.perform(get("/api/countries"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void with_valid_token_returns_countries_sorted_by_korean_name() throws Exception {
        mockMvc.perform(get("/api/countries").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(20))
                .andExpect(jsonPath("$[0].nameKo").value("대만"))
                .andExpect(jsonPath("$[0].isoAlpha2").value("TW"))
                .andExpect(jsonPath("$[0].tier").value("A"));
    }

    @Test
    void health_is_accessible_without_token() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk());
    }

    @Test
    void 국가_상세_정보를_camelCase로_반환한다() throws Exception {
        mockMvc.perform(get("/api/countries/VN").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isoAlpha2").value("VN"))
                .andExpect(jsonPath("$.nameKo").value("베트남"))
                .andExpect(jsonPath("$.tier").value("A"));
    }

    @Test
    void 존재하지_않는_국가_상세는_404() throws Exception {
        mockMvc.perform(get("/api/countries/ZZ").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }

    @Test
    void 준비물_체크리스트는_공통_템플릿_8개를_우선순위순으로_반환한다() throws Exception {
        mockMvc.perform(get("/api/countries/VN/checklist").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(8))
                .andExpect(jsonPath("$[0].title").value("플러그 어댑터 준비"))
                .andExpect(jsonPath("$[0].category").value("POWER"));
    }
}
