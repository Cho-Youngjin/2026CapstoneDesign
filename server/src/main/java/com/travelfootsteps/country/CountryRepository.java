package com.travelfootsteps.country;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

// JpaRepository<Country, Long>을 상속만 하면, 구현 클래스를 직접 안 써도 스프링 데이터 JPA가
// 실행 시점에 프록시 구현체를 자동으로 만들어준다. save(), findById(), findAll(), delete() 같은
// 기본 CRUD 메서드는 이미 JpaRepository에 다 들어있어서 따로 선언할 필요가 없다.
public interface CountryRepository extends JpaRepository<Country, Long> {

    // 메서드 이름만으로 쿼리를 만들어내는 기능("쿼리 메서드")이다.
    // findByIsoAlpha2 -> "isoAlpha2 필드로 조회해라"는 뜻이고, 이름을 분석해서
    // `WHERE iso_alpha2 = ?` 같은 SQL을 스프링 데이터 JPA가 자동 생성한다. SQL을 직접 안 써도 된다.
    Optional<Country> findByIsoAlpha2(String isoAlpha2);

    // findAllByOrderByNameKoAsc -> "전체를 nameKo 오름차순으로 정렬해서 가져와라".
    // 이것도 메서드 이름 규칙(OrderBy + 필드명 + Asc/Desc)만으로 정렬 쿼리가 만들어진다.
    List<Country> findAllByOrderByNameKoAsc();
}
