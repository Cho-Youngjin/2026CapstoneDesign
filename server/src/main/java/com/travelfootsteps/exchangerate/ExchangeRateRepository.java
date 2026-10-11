package com.travelfootsteps.exchangerate;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

// JpaRepository<ExchangeRate, Long>을 상속하면 save/findAll/count 같은 기본 CRUD
// 메서드를 스프링 데이터 JPA가 자동으로 구현해준다. 아래 메서드들은 메서드 이름만으로
// 스프링 데이터 JPA가 SQL을 자동 생성하는 쿼리 메서드다 — 구현체를 직접 작성할 필요가 없다.
public interface ExchangeRateRepository extends JpaRepository<ExchangeRate, Long> {

    // "WHERE currency_code = ?"
    Optional<ExchangeRate> findByCurrencyCode(String currencyCode);

    // "WHERE source = ? 인 행이 하나라도 있는가?" — 수출입은행 행이 아예 없는 상태(첫 보정 실패)를
    // 기동 시 보정 실행 조건에서 가려내는 데 쓴다.
    boolean existsBySource(RateSource source);

    // "출처가 source이면서 previous_krw_rate가 NULL인 행이 하나라도 있는가?" — exists로 시작하는 쿼리
    // 메서드는 boolean을 돌려준다. 기동 시 보정 실행이 필요한지 판단하는 데 쓴다(설계 §4.4).
    boolean existsBySourceAndPreviousKrwRateIsNull(RateSource source);
}
