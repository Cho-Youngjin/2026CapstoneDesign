package com.travelfootsteps.trip;

import com.travelfootsteps.visa.VisaJudgement;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.OffsetDateTime;

// @Entity + @Table(name = "trip"): 이 클래스가 trip 테이블의 한 행과 매핑되는 JPA 엔티티임을
// 선언한다 (V4__trip.sql 참고).
// @Getter(Lombok): 모든 필드에 대해 getXxx()를 자동 생성한다. boolean 필드(passportOk)는
// Lombok 관례상 isPassportOk()로 생성된다.
// @NoArgsConstructor(access = PROTECTED): JPA가 리플렉션으로 인스턴스를 만들 때 필요한 기본
// 생성자다. 외부 코드가 `new Trip()`으로 빈 객체를 만들지 못하게 protected로 좁혔다 — 새 행은
// 아래 create() 팩토리 메서드로만 만들 수 있다.
@Entity
@Table(name = "trip")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Trip {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "firebase_uid", nullable = false, length = 128)
    private String firebaseUid;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(name = "depart_date", nullable = false)
    private LocalDate departDate;

    @Column(name = "return_date", nullable = false)
    private LocalDate returnDate;

    @Column(name = "passport_expiry", nullable = false)
    private LocalDate passportExpiry;

    // ─── 판정 스냅샷 (2026-09-12 리뷰로 추가) ───────────────────────────────────
    // 아래 7개 필드는 VisaJudgementService.judge()의 결과를 "그 순간 그대로" 얼려서 저장한 것이다.
    // TripController.create()가 딱 한 번 채우고, TripController.get()은 이 필드들을 읽기만
    // 할 뿐 judge()를 다시 부르지 않는다 — 원본 visa_requirement가 나중에 바뀌어도 이미 확정된
    // 여행의 판정과 trip_task(및 앱이 그걸 보고 예약해 둔 로컬 알람)가 조용히 어긋나지 않게
    // 하려는 의도적 설계다. verdict는 String으로 저장한다(VisaVerdict enum을 그대로 저장하지
    // 않는 이유: 이 프로젝트의 API 계약은 enum이 아니라 VisaVerdict.wireValue() 문자열이고,
    // Trip은 그 문자열을 저장했다가 그대로 응답에 돌려주는 역할만 하면 충분하기 때문이다).
    @Column(nullable = false, length = 30)
    private String verdict;

    @Column(name = "stay_days", nullable = false)
    private int stayDays;

    // null 허용: VisaJudgement.visaFreeDays()가 null일 수 있다(요건 미수집/파싱 실패 = UNVERIFIED).
    @Column(name = "visa_free_days")
    private Integer visaFreeDays;

    @Column(name = "passport_ok", nullable = false)
    private boolean passportOk;

    @Column(name = "passport_validity_months")
    private Integer passportValidityMonths;

    @Column(name = "passport_shortfall_days")
    private Integer passportShortfallDays;

    // 스냅샷을 만들 때 사용한 visa_requirement 행의 source_fetched_at을 그대로 복사해 둔다.
    // GET/refresh가 "그 나라의 현재" source_fetched_at과 이 값을 비교해서 다르면 데이터가 그
    // 사이에 바뀌었다는 뜻이다(judgementStale). 여행을 만들 당시 그 나라의 visa_requirement가
    // 아예 없었다면(UNVERIFIED) null이 저장된다.
    @Column(name = "requirement_updated_at")
    private OffsetDateTime requirementUpdatedAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /**
     * 새 여행을 만든다. 판정 스냅샷은 비워둔 채로 반환하므로, 호출부(TripController)가 반드시
     * {@link #applyJudgementSnapshot}을 이어서 호출해 채워야 한다 — 두 단계로 나눈 이유는
     * {@link #applyJudgementSnapshot}을 새로고침({@code POST /api/trips/{id}/refresh})에서도
     * 그대로 재사용하기 위해서다.
     */
    public static Trip create(String firebaseUid, Long countryId, LocalDate departDate,
                               LocalDate returnDate, LocalDate passportExpiry) {
        Trip trip = new Trip();
        trip.firebaseUid = firebaseUid;
        trip.countryId = countryId;
        trip.departDate = departDate;
        trip.returnDate = returnDate;
        trip.passportExpiry = passportExpiry;
        trip.createdAt = OffsetDateTime.now();
        return trip;
    }

    /**
     * 판정 스냅샷 컬럼을 (덮어)쓴다. 생성 시 한 번, 새로고침 시 한 번 더 호출되는 것 외에는
     * 절대 호출되지 않는다 — 즉 "언제 스냅샷이 바뀌는가"가 이 메서드 호출 지점 두 곳으로 고정돼
     * 있다는 것 자체가 이 설계의 핵심이다(조회는 스냅샷을 바꾸지 않는다).
     *
     * @param requirementUpdatedAt 판정에 사용한 visa_requirement 행의 source_fetched_at.
     *                             그 나라의 요건이 아직 수집되지 않았다면(UNVERIFIED) null.
     */
    public void applyJudgementSnapshot(VisaJudgement judgement, OffsetDateTime requirementUpdatedAt) {
        this.verdict = judgement.verdict().wireValue();
        this.stayDays = judgement.stayDays();
        this.visaFreeDays = judgement.visaFreeDays();
        this.passportOk = judgement.passportOk();
        this.passportValidityMonths = judgement.passportValidityMonths();
        this.passportShortfallDays = judgement.passportShortfallDays();
        this.requirementUpdatedAt = requirementUpdatedAt;
    }

    public boolean belongsTo(String firebaseUid) {
        return this.firebaseUid.equals(firebaseUid);
    }
}
