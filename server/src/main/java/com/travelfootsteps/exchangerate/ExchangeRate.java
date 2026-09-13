package com.travelfootsteps.exchangerate;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.time.LocalDate;

// @Entity + @Table(name = "exchange_rate"): V6__exchange_rate.sql의 exchange_rate 테이블과
// 매핑되는 JPA 엔티티다. 통화코드(currency_code)당 딱 한 행만 존재하는 캐시이므로(UNIQUE 제약),
// 이 클래스에는 이력 개념이 없다 — of()로 처음 만들고 이후에는 update()로 그 한 행을 계속
// 덮어쓴다(Task 9 배치 스케줄러의 upsert 로직 참고).
// @NoArgsConstructor(access = PROTECTED): JPA가 리플렉션으로 인스턴스를 생성할 때 필요한
// 기본 생성자다. 외부 코드가 `new ExchangeRate()`로 빈 객체를 만들 수 없도록 protected로 좁혔다.
@Entity
@Table(name = "exchange_rate")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ExchangeRate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    // CHAR(3)로 매핑하는 이유는 Country.isoAlpha2/isoAlpha3 필드의 주석과 동일하다 —
    // columnDefinition만으로는 DDL 생성 문자열만 바뀌고 Hibernate 내부 타입 코드는 VARCHAR로
    // 남아, ddl-auto=validate가 실제 DB의 CHAR(bpchar) 컬럼과 비교할 때 SchemaManagementException을
    // 던진다. @JdbcTypeCode(SqlTypes.CHAR)를 함께 붙여야 검증이 통과한다.
    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "currency_code", nullable = false, unique = true, length = 3, columnDefinition = "CHAR(3)")
    private String currencyCode;

    @Column(name = "krw_rate", nullable = false, precision = 12, scale = 4)
    private BigDecimal krwRate;

    @Column(name = "base_date", nullable = false)
    private LocalDate baseDate;

    // 새 통화의 첫 캐시 행을 만드는 정적 팩토리 메서드. 배치가 아직 캐시에 없는 통화코드를
    // 만나면 이 메서드로 새 행을 만들어 저장한다.
    public static ExchangeRate of(String currencyCode, BigDecimal krwRate, LocalDate baseDate) {
        ExchangeRate rate = new ExchangeRate();
        rate.currencyCode = currencyCode;
        rate.krwRate = krwRate;
        rate.baseDate = baseDate;
        return rate;
    }

    // 이미 캐시된 통화의 환율/기준일을 갱신한다. JPA 영속성 컨텍스트 안에서 필드만 바꾸면
    // 트랜잭션 커밋 시점에 변경 감지(dirty checking)로 자동 UPDATE 되므로, 별도의 save() 호출이
    // 필요 없다(ExchangeRateBatchScheduler.upsert() 참고).
    public void update(BigDecimal krwRate, LocalDate baseDate) {
        this.krwRate = krwRate;
        this.baseDate = baseDate;
    }
}
