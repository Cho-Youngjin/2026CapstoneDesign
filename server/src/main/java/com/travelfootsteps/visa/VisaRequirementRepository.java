package com.travelfootsteps.visa;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

// @Repository를 따로 붙이지 않아도 된다 — JpaRepository를 상속한 인터페이스는 스프링 데이터 JPA가
// 부팅 시점에 자동으로 찾아서(컴포넌트 스캔과는 다른 별도 메커니즘) 프록시 구현체를 만들어주고,
// 그 구현체 자체에 이미 @Repository 성격(DB 예외를 스프링의 공통 DataAccessException으로 변환)이
// 들어있다. save(), findById() 같은 기본 CRUD 메서드는 JpaRepository에 이미 들어있어 선언할 필요가
// 없다.
public interface VisaRequirementRepository extends JpaRepository<VisaRequirement, Long> {

    // 쿼리 메서드: 메서드 이름(countryId + passportType 필드)만으로 스프링 데이터 JPA가
    // `WHERE country_id = ? AND passport_type = ?` 쿼리를 자동 생성한다.
    // VisaRequirementCollector가 upsert 대상 행을 찾을 때(있으면 갱신, 없으면 새로 생성) 이 메서드를 쓴다.
    Optional<VisaRequirement> findByCountryIdAndPassportType(Long countryId, String passportType);
}
