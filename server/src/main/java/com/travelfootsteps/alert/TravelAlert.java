package com.travelfootsteps.alert;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

// @Entity + @Table: 이 클래스를 travel_alert 테이블 한 줄(row)과 매핑한다(V3 마이그레이션 참고).
// 여행경보는 "국가당 현재 상태"만 의미가 있고 국가당 여러 건이 나올 수 있어서(지역별 경보),
// VisaRequirement처럼 단일 행을 upsert하는 대신 TravelAlertCollector가 국가의 기존 행을
// 전부 지우고 새로 받아온 것으로 교체하는 전략을 쓴다 — 이 엔티티 자체는 그 전략을 몰라도 된다.
// @Getter(Lombok): 모든 필드에 getXxx()를 자동 생성한다.
// @NoArgsConstructor(PROTECTED): JPA가 리플렉션으로 객체를 만들 때 필요한 기본 생성자이되,
// 외부에서 `new TravelAlert()`로 빈 객체를 만들지 못하도록 접근 범위를 좁혀둔다.
@Entity
@Table(name = "travel_alert")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TravelAlert {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    // level: 0(UNKNOWN, 파싱 실패/미확인) ~ 4(여행금지) 사이의 값. V3 마이그레이션의
    // CHECK (level BETWEEN 0 AND 4) 제약과 짝을 이룬다.
    @Column(nullable = false)
    private int level;

    @Column(length = 100)
    private String region;

    @Column(nullable = false, length = 255)
    private String title;

    @Column(name = "issued_at", nullable = false)
    private OffsetDateTime issuedAt;

    // @Builder(Lombok): 아래 생성자를 기반으로 TravelAlert.builder()....build() 형태의
    // 빌더 API를 만들어준다. 필드가 여러 개일 때 생성자 호출보다 어떤 값이 어떤 필드로
    // 들어가는지 읽기 쉽다.
    @Builder
    public TravelAlert(Long countryId, int level, String region, String title, OffsetDateTime issuedAt) {
        this.countryId = countryId;
        this.level = level;
        this.region = region;
        this.title = title;
        this.issuedAt = issuedAt;
    }
}
