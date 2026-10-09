package com.travelfootsteps.exchangerate;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

// @Entity + @Table(name = "exchange_rate"): V6__exchange_rate.sql(+ V10에서 컬럼 추가)의 exchange_rate
// 테이블과 매핑되는 JPA 엔티티다. 통화코드(currency_code)당 딱 한 행만 존재하는 캐시이고(UNIQUE 제약),
// 이력 대신 "직전 고시일 값" 한 칸(previousKrwRate/previousBaseDate)만 들고 있다 — 전 영업일 대비
// 등락을 계산하는 데는 그 한 칸이면 충분하다(지갑·환율 알림 설계 §4.2).
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

    // 항상 "통화 1단위당 원화"다. 수출입은행의 JPY(100)·IDR(100)은 배치가 100으로 나눠서 넣는다.
    @Column(name = "krw_rate", nullable = false, precision = 18, scale = 6)
    private BigDecimal krwRate;

    // 이 환율이 고시된 날짜(영업일). 배치를 돌린 날짜가 아니다.
    @Column(name = "base_date", nullable = false)
    private LocalDate baseDate;

    // 직전 고시일의 환율과 그 날짜. 아직 하루치만 받았으면 null이고, 이때 등락은 계산하지 않는다.
    @Column(name = "previous_krw_rate", precision = 18, scale = 6)
    private BigDecimal previousKrwRate;

    @Column(name = "previous_base_date")
    private LocalDate previousBaseDate;

    // @Enumerated(EnumType.STRING): enum을 DB에 "EXIM" 같은 이름 문자열로 저장한다.
    // 기본값(ORDINAL)은 0, 1 같은 순서 번호로 저장해서, 나중에 enum 순서가 바뀌면 기존 데이터의
    // 의미가 조용히 뒤바뀐다 — 그래서 문자열 저장을 명시한다.
    @Enumerated(EnumType.STRING)
    @Column(name = "source", nullable = false, length = 10)
    private RateSource source;

    // 새 통화의 첫 캐시 행을 만드는 정적 팩토리 메서드. 배치가 아직 캐시에 없는 통화코드를
    // 만나면 이 메서드로 새 행을 만들어 저장한다.
    public static ExchangeRate of(String currencyCode, BigDecimal krwRate, LocalDate baseDate, RateSource source) {
        ExchangeRate rate = new ExchangeRate();
        rate.currencyCode = currencyCode;
        rate.krwRate = krwRate;
        rate.baseDate = baseDate;
        rate.source = source;
        return rate;
    }

    // 출처를 생략하면 수출입은행 값으로 본다(기존 호출부·테스트 호환).
    public static ExchangeRate of(String currencyCode, BigDecimal krwRate, LocalDate baseDate) {
        return of(currencyCode, krwRate, baseDate, RateSource.EXIM);
    }

    /**
     * 새로 받은 환율을 이 캐시 행에 반영한다(설계 §4.3).
     *
     * <ul>
     *   <li>더 늦은 고시일: 지금 값을 이전값 칸으로 밀어내고 새 값을 현재값으로 삼는다.</li>
     *   <li>같은 고시일: 같은 날 배치가 여러 번 돌았거나 값이 정정된 경우다. 현재값만 바꾸고 이전값은 둔다.</li>
     *   <li>더 이른 고시일: 기동 시 보정 실행이 과거 영업일을 채울 때다. 이전값 칸이 비어 있을 때만 채운다.</li>
     * </ul>
     *
     * <p>JPA 영속성 컨텍스트 안에서 필드만 바꾸면 트랜잭션 커밋 시점에 변경 감지(dirty checking)로
     * 자동 UPDATE 되므로, 이 메서드를 부른 쪽은 별도로 save()를 호출할 필요가 없다.
     */
    public void apply(BigDecimal rate, LocalDate date, RateSource source) {
        if (date.isAfter(baseDate)) {
            this.previousKrwRate = this.krwRate;
            this.previousBaseDate = this.baseDate;
            this.krwRate = rate;
            this.baseDate = date;
            this.source = source;
        } else if (date.isEqual(baseDate)) {
            this.krwRate = rate;
            this.source = source;
        } else if (this.previousBaseDate == null) {
            this.previousKrwRate = rate;
            this.previousBaseDate = date;
        }
    }

    // 전 영업일 대비 등락률(%). 소수 둘째 자리 반올림. 이전값이 없거나 0이면 계산할 수 없어 null.
    public BigDecimal changePercent() {
        if (previousKrwRate == null || previousKrwRate.signum() == 0) {
            return null;
        }
        return krwRate.subtract(previousKrwRate)
                .multiply(BigDecimal.valueOf(100))
                .divide(previousKrwRate, 2, RoundingMode.HALF_UP);
    }
}
