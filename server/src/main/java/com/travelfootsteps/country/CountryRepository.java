package com.travelfootsteps.country;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CountryRepository extends JpaRepository<Country, Long> {

    Optional<Country> findByIsoAlpha2(String isoAlpha2);

    List<Country> findAllByOrderByNameKoAsc();
}
