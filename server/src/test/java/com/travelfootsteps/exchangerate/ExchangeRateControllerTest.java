package com.travelfootsteps.exchangerate;

import com.travelfootsteps.auth.TokenVerifier;
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

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(ExchangeRateControllerTest.TestBeans.class)
class ExchangeRateControllerTest {

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
    @Autowired ExchangeRateRepository repository;

    @Test
    void 캐시된_환율을_반환한다() throws Exception {
        repository.save(ExchangeRate.of("VND", new BigDecimal("0.0540"), LocalDate.of(2026, 9, 7)));

        mockMvc.perform(get("/api/exchange-rates/VND").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currencyCode").value("VND"))
                .andExpect(jsonPath("$.krwRate").value(0.0540));
    }

    @Test
    void 캐시에_없는_통화는_404() throws Exception {
        mockMvc.perform(get("/api/exchange-rates/XXX").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }

    @Test
    void 소문자_통화코드도_대문자로_정규화해서_조회한다() throws Exception {
        repository.save(ExchangeRate.of("USD", new BigDecimal("1320.5000"), LocalDate.of(2026, 9, 7)));

        mockMvc.perform(get("/api/exchange-rates/usd").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currencyCode").value("USD"));
    }

    @Test
    void 토큰_없이_요청하면_401() throws Exception {
        mockMvc.perform(get("/api/exchange-rates/VND"))
                .andExpect(status().isUnauthorized());
    }
}
