package com.travelfootsteps.country;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class CountryRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void flyway(DynamicPropertyRegistry registry) {
        registry.add("spring.flyway.enabled", () -> "true");
    }

    @Autowired
    CountryRepository countryRepository;

    @Test
    void seed_contains_20_tier_a_countries() {
        assertThat(countryRepository.findAll()).hasSize(20);
    }

    @Test
    void findByIsoAlpha2_returns_country() {
        Optional<Country> vietnam = countryRepository.findByIsoAlpha2("VN");

        assertThat(vietnam).isPresent();
        assertThat(vietnam.get().getNameKo()).isEqualTo("베트남");
        assertThat(vietnam.get().getTier()).isEqualTo("A");
    }

    @Test
    void findAllByOrderByNameKoAsc_is_sorted() {
        var names = countryRepository.findAllByOrderByNameKoAsc()
                .stream().map(Country::getNameKo).toList();

        assertThat(names).isSorted();
    }
}
