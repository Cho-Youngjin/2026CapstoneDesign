package com.travelfootsteps.alert;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

// JpaRepository<TravelAlert, Long>를 상속하기만 하면 스프링 데이터 JPA가 구현체를 런타임에
// 자동으로 만들어준다. 아래 두 메서드는 "쿼리 메서드" 규칙(메서드 이름 -> SQL 자동 생성)을 쓴다.
public interface TravelAlertRepository extends JpaRepository<TravelAlert, Long> {

    // findByCountryIdOrderByIssuedAtDesc -> "country_id로 조회하고 issued_at 내림차순 정렬".
    // 컨트롤러가 최신 경보를 앞에 보여줄 때 그대로 쓴다.
    List<TravelAlert> findByCountryIdOrderByIssuedAtDesc(Long countryId);

    // 국가 하나의 기존 경보를 전부 지운다 — TravelAlertCollector의 "교체(replace)" 전략에서
    // 새로 수집한 데이터를 넣기 전에 호출된다.
    void deleteByCountryId(Long countryId);
}
