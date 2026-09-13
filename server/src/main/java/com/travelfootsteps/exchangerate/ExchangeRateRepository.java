package com.travelfootsteps.exchangerate;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

// JpaRepository<ExchangeRate, Long>을 상속하면 save/findAll/deleteById 같은 기본 CRUD
// 메서드를 스프링 데이터 JPA가 자동으로 구현해준다. 아래 findByCurrencyCode는 메서드 이름만으로
// 스프링 데이터 JPA가 "WHERE currency_code = ?" 쿼리를 자동 생성하는 쿼리 메서드다 — 구현체를
// 직접 작성할 필요가 없다.
public interface ExchangeRateRepository extends JpaRepository<ExchangeRate, Long> {
    Optional<ExchangeRate> findByCurrencyCode(String currencyCode);
}
