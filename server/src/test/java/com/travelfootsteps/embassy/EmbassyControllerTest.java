package com.travelfootsteps.embassy;

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

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(EmbassyControllerTest.TestBeans.class)
class EmbassyControllerTest {

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
    @Autowired EmbassyRepository embassyRepository;

    @Test
    void 국가의_재외공관_목록을_반환한다() throws Exception {
        Country japan = countryRepository.findByIsoAlpha2("JP").orElseThrow();
        embassyRepository.save(Embassy.builder()
                .countryId(japan.getId()).type("대사관").name("주일본 대한민국 대사관")
                .lat(35.6762).lng(139.7503).phone("+81-3-0000-0000")
                .emergencyPhone("+81-90-0000-0000").address("Tokyo").build());

        mockMvc.perform(get("/api/countries/JP/embassies").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("주일본 대한민국 대사관"))
                .andExpect(jsonPath("$[0].lat").value(35.6762));
    }

    @Test
    void 존재하지_않는_국가는_404() throws Exception {
        mockMvc.perform(get("/api/countries/ZZ/embassies").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isNotFound());
    }
}
