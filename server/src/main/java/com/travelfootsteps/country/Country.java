package com.travelfootsteps.country;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

// @Entity: 이 클래스가 DB 테이블 한 줄(row)과 매핑되는 "엔티티"임을 JPA(Hibernate)에게 알린다.
// @Table(name = "country")로 어떤 테이블에 매핑되는지 지정한다(생략하면 클래스명을 그대로 쓴다).
// @Getter(Lombok)는 모든 필드에 대해 getXxx() 메서드를 자동 생성해준다 — isoAlpha2 필드가 있으면
// getIsoAlpha2()가 자동으로 생긴다는 뜻이다.
// @NoArgsConstructor(access = PROTECTED): JPA는 리플렉션으로 객체를 만들기 때문에 매개변수 없는
// 생성자가 반드시 있어야 한다. 그런데 외부 코드가 실수로 `new Country()`(빈 객체)를 만들지 못하게
// 막고 싶어서, public이 아니라 protected로 좁혀뒀다 — JPA는 protected여도 접근 가능하다.
@Entity
@Table(name = "country")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Country {

    // @Id + @GeneratedValue(IDENTITY): 이 필드가 기본키(PK)이고, 값은 DB가 auto-increment로
    // 알아서 채워준다는 뜻이다 (V1__init.sql의 BIGSERIAL과 짝을 이룬다).
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // @Column으로 이 필드가 매핑되는 실제 컬럼명/제약조건을 지정한다. length는 자바 문자열의
    // 최대 길이 힌트이고, columnDefinition은 DB에 실제로 어떤 타입으로 만들지를 강제로 지정한다.
    // @JdbcTypeCode(SqlTypes.CHAR)를 함께 붙인 이유: columnDefinition만으로는 DDL 생성 문자열만
    // 바뀔 뿐, Hibernate가 "이 컬럼은 VARCHAR일 것이다"라고 내부적으로 기억하는 타입 코드는 안
    // 바뀐다. 그래서 ddl-auto=validate가 실제 DB의 CHAR(bpchar) 컬럼과 비교할 때 "VARCHAR인 줄
    // 알았는데 CHAR네?"라며 SchemaManagementException을 던진다. @JdbcTypeCode(SqlTypes.CHAR)를
    // 추가로 붙여야 Hibernate가 이 필드를 진짜 CHAR 타입으로 취급해서 검증이 통과한다.
    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "iso_alpha2", nullable = false, unique = true, length = 2, columnDefinition = "CHAR(2)")
    private String isoAlpha2;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "iso_alpha3", length = 3, columnDefinition = "CHAR(3)")
    private String isoAlpha3;

    @Column(name = "name_ko", nullable = false, length = 100)
    private String nameKo;

    @Column(name = "name_en", length = 100)
    private String nameEn;

    @Column(length = 50)
    private String continent;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(nullable = false, length = 1, columnDefinition = "CHAR(1)")
    private String tier;

    @Column(name = "plug_types", length = 50)
    private String plugTypes;

    @Column(name = "voltage_v")
    private Integer voltageV;

    @Column(name = "frequency_hz")
    private Integer frequencyHz;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "currency_code", length = 3, columnDefinition = "CHAR(3)")
    private String currencyCode;

    @Column(name = "card_acceptance", length = 10)
    private String cardAcceptance;

    @Column(name = "power_bank_wh_limit")
    private Integer powerBankWhLimit;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;
}
