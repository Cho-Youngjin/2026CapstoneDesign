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

import static org.hamcrest.Matchers.nullValue;
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
    void 이전값과_등락률_출처를_함께_반환한다() throws Exception {
        ExchangeRate jpy = ExchangeRate.of("JPY", new BigDecimal("8.4"), LocalDate.of(2026, 10, 7), RateSource.EXIM);
        jpy.apply(new BigDecimal("8.4746"), LocalDate.of(2026, 10, 8), RateSource.EXIM);
        repository.save(jpy);

        mockMvc.perform(get("/api/exchange-rates/JPY").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.krwRate").value(8.4746))
                .andExpect(jsonPath("$.baseDate").value("2026-10-08"))
                .andExpect(jsonPath("$.previousKrwRate").value(8.4))
                .andExpect(jsonPath("$.previousBaseDate").value("2026-10-07"))
                .andExpect(jsonPath("$.changePercent").value(0.89))
                .andExpect(jsonPath("$.source").value("EXIM"));
    }

    @Test
    void 이전값이_없으면_등락_필드는_null이다() throws Exception {
        repository.save(ExchangeRate.of("GBP", new BigDecimal("1790.12"), LocalDate.of(2026, 10, 8)));

        mockMvc.perform(get("/api/exchange-rates/GBP").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.previousKrwRate").value(nullValue()))
                .andExpect(jsonPath("$.previousBaseDate").value(nullValue()))
                .andExpect(jsonPath("$.changePercent").value(nullValue()));
    }

    @Test
    void 참고환율은_출처가_ER_API로_나간다() throws Exception {
        repository.save(ExchangeRate.of("TWD", new BigDecimal("41.970956"), LocalDate.of(2026, 10, 9), RateSource.ER_API));

        mockMvc.perform(get("/api/exchange-rates/TWD").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.krwRate").value(41.970956))
                .andExpect(jsonPath("$.source").value("ER_API"));
    }

    @Test
    void 토큰_없이도_환율을_조회할_수_있다() throws Exception {
        repository.save(ExchangeRate.of("EUR", new BigDecimal("1500.04"), LocalDate.of(2026, 10, 8)));

        mockMvc.perform(get("/api/exchange-rates/EUR"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.currencyCode").value("EUR"));
    }

    @Test
    void 환율이_아닌_다른_API는_여전히_토큰이_필요하다() throws Exception {
        mockMvc.perform(get("/api/countries/JP"))
                .andExpect(status().isUnauthorized());
    }
}
