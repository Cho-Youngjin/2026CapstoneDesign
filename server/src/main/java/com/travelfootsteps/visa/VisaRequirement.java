package com.travelfootsteps.visa;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

// @Entity + @Table(name = "visa_requirement"): 이 클래스가 visa_requirement 테이블의 한 행과
// 매핑되는 JPA 엔티티임을 선언한다(V2__visa_requirement.sql 참고).
// @Getter(Lombok): 모든 필드에 대해 getXxx()를 자동 생성한다. boolean 필드(visaRequired, verified)는
// Lombok 관례상 getXxx()가 아니라 isXxx()로 생성된다(isVisaRequired(), isVerified()).
// @NoArgsConstructor(access = PROTECTED): JPA가 리플렉션으로 인스턴스를 만들 때 필요한 기본
// 생성자다. 외부 코드가 `new VisaRequirement()`로 빈 객체를 만들지 못하게 protected로 좁혔다 —
// 새 행은 아래 newUnverified() 팩토리 메서드로만 만들 수 있다.
//
// 배치 흐름에서의 위치: Task 4의 스케줄러 -> VisaRequirementCollector.collectOne(country) ->
// (신규면) newUnverified()로 뼈대를 만들고 applyCollectedData()로 파싱 결과를 채움, 또는
// (기존 unverified 행이면) applyCollectedData()로 덮어씀, 또는 (verified=true인 Tier A 행이면)
// refreshSourceOnly()로 원문 참고자료만 갱신 -> VisaRequirementRepository.save()로 DB에 반영.
@Entity
@Table(name = "visa_requirement")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class VisaRequirement {

    // @Id + @GeneratedValue(IDENTITY): 기본키이며 DB(BIGSERIAL)가 auto-increment로 값을 채운다.
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    // 이 수집기는 GENERAL(일반 여권)만 다룬다 — OFFICIAL/DIPLOMATIC은 스키마(CHECK 제약)가
    // 미래를 위해 허용해둔 값일 뿐, 이 컬렉터는 절대 그 값으로 행을 만들지 않는다.
    @Column(name = "passport_type", nullable = false, length = 10)
    private String passportType;

    @Column(name = "visa_required", nullable = false)
    private boolean visaRequired;

    // null 허용: 파싱 실패(원문에서 확신 있게 숫자를 못 뽑음)를 의미한다.
    // ParsedVisaCondition 클래스 문서에 null 의미를 자세히 설명해뒀다.
    @Column(name = "visa_free_days")
    private Integer visaFreeDays;

    // null 허용: 원문에 여권 잔여유효기간 요건 언급이 아예 없다는 뜻(요건이 없는 것으로 간주).
    @Column(name = "passport_validity_months")
    private Integer passportValidityMonths;

    @Column(name = "raw_text", columnDefinition = "TEXT")
    private String rawText;

    @Column(name = "evidence_text", columnDefinition = "TEXT")
    private String evidenceText;

    @Column(columnDefinition = "TEXT")
    private String remark;

    @Column(name = "source_fetched_at", nullable = false)
    private OffsetDateTime sourceFetchedAt;

    // true면 사람이 수기로 검증한 Tier A 행이라는 뜻이다. 이 플래그가 true인 행은
    // 재수집 시 판정 필드(visaRequired/visaFreeDays/passportValidityMonths)를 절대 덮어쓰지
    // 않는다 — 수기 검증 데이터 보존이 이 테이블 설계 전체를 떠받치는 전제다. 이 플래그를
    // 세우는 공개 API는 이 계획(Plan A)에 의도적으로 없다(수기 검증은 별도 운영 프로세스/직접
    // SQL로 처리한다).
    @Column(nullable = false)
    private boolean verified;

    /** 아직 검증되지 않은 새 행의 뼈대를 만든다. verified는 false로 시작한다. */
    public static VisaRequirement newUnverified(Long countryId, String passportType) {
        VisaRequirement v = new VisaRequirement();
        v.countryId = countryId;
        v.passportType = passportType;
        v.verified = false;
        return v;
    }

    // 패키지 프라이빗(접근 제한자 없음): 이 메서드는 같은 패키지(com.travelfootsteps.visa)의
    // VisaRequirementCollector만 호출할 수 있다. 판정 필드를 바꾸는 유일한 통로를 수집기로
    // 좁혀서, 다른 패키지가 실수로(또는 검증 없이) 판정 필드를 직접 덮어쓰는 일을 막는다.
    /** 파싱 결과와 원문을 전부 갱신한다. verified=true인 행에는 호출하면 안 된다(호출부가 분기 책임). */
    void applyCollectedData(ParsedVisaCondition parsed, String rawText, String evidenceText,
                             String remark, OffsetDateTime fetchedAt) {
        this.visaRequired = parsed.visaRequired();
        this.visaFreeDays = parsed.visaFreeDays();
        this.passportValidityMonths = parsed.passportValidityMonths();
        this.rawText = rawText;
        this.evidenceText = evidenceText;
        this.remark = remark;
        this.sourceFetchedAt = fetchedAt;
    }

    // 패키지 프라이빗: applyCollectedData()와 같은 이유로 접근을 VisaRequirementCollector로 좁힌다.
    /** verified=true인 Tier A 행은 판정 필드를 건드리지 않고 원문 참고자료만 최신화한다. */
    void refreshSourceOnly(String rawText, String evidenceText, String remark, OffsetDateTime fetchedAt) {
        this.rawText = rawText;
        this.evidenceText = evidenceText;
        this.remark = remark;
        this.sourceFetchedAt = fetchedAt;
    }
}
