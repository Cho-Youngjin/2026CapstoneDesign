package com.travelfootsteps.alert;

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

import java.time.OffsetDateTime;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(TravelAlertControllerTest.TestBeans.class)
class TravelAlertControllerTest {

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
    @Autowired TravelAlertRepository travelAlertRepository;

    @Test
    void 국가의_여행경보_목록을_최신순으로_반환한다() throws Exception {
        Country vietnam = countryRepository.findByIsoAlpha2("VN").orElseThrow();
        travelAlertRepository.save(TravelAlert.builder()
                .countryId(vietnam.getId()).level(2).region("전역").title("여행자제")
                .issuedAt(OffsetDateTime.now()).build());

        mockMvc.perform(get("/api/countries/VN/alerts").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].level").value(2))
                .andExpect(jsonPath("$[0].title").value("여행자제"));
    }

    @Test
    void 존재하지_않는_국가는_404() throws Exception {
        mockMvc.perform(get("/api/countries/ZZ/alerts").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }
}
