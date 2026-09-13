package com.travelfootsteps.visa;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class VisaJudgementServiceTest {

    private final VisaJudgementService service = new VisaJudgementService();

    private VisaRequirement requirement(boolean visaRequired, Integer visaFreeDays, Integer passportMonths) {
        VisaRequirement r = VisaRequirement.newUnverified(1L, "GENERAL");
        r.applyCollectedData(new ParsedVisaCondition(visaRequired, visaFreeDays, passportMonths),
                "raw", null, null, OffsetDateTime.now());
        return r;
    }

    @Test
    void 스펙_예시_베트남_20일_체류_45일_무비자_여권잔여85일_6개월요건_미달() {
        // 스펙 §6-① 예시: 2026-12-20 출발, 20일 체류, 여권만료 2027-03-15
        VisaRequirement req = requirement(false, 45, 6);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 3, 15));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_FREE_OK);
        assertThat(judgement.stayDays()).isEqualTo(20);
        assertThat(judgement.passportOk()).isFalse(); // 6개월(180일) 요건에 여권잔여 부족
    }

    @Test
    void returnDate가_departDate보다_앞서면_stayDays가_음수이므로_UNVERIFIED다() {
        // 컨트롤러 레벨(CreateTripRequest의 @AssertTrue)이 이미 이런 요청을 400으로 막지만,
        // judge()는 다른 호출부를 신뢰하지 않는 두 번째 방어선으로서 스스로도 불가능한 날짜
        // 범위에 대해 "무비자 OK" 같은 판정을 조용히 내놓으면 안 된다.
        VisaRequirement req = requirement(false, 45, 6);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2027, 1, 9), LocalDate.of(2026, 12, 20),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.UNVERIFIED);
        assertThat(judgement.stayDays()).isLessThan(0);
    }

    @Test
    void visa_free_days가_null이면_무조건_UNVERIFIED() {
        VisaRequirement req = requirement(false, null, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.UNVERIFIED);
    }

    @Test
    void visa_requirement_행_자체가_없으면_UNVERIFIED() {
        VisaJudgement judgement = service.judge(null,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.UNVERIFIED);
    }

    @Test
    void visa_required가_true여도_visaFreeDays가_null이면_UNVERIFIED가_우선한다() {
        // visaRequired=true라면 언뜻 VISA_REQUIRED로 보이지만, visaFreeDays를 파싱하지 못한
        // (null) 상태이므로 다른 어떤 조건보다 UNVERIFIED가 최우선이어야 한다.
        VisaRequirement req = requirement(true, null, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.UNVERIFIED);
    }

    @Test
    void 무비자_체류일수_초과는_VISA_FREE_EXCEEDED() {
        VisaRequirement req = requirement(false, 15, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), // 20일 체류
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_FREE_EXCEEDED);
    }

    @Test
    void 체류일수가_무비자_한도와_정확히_같으면_초과가_아니라_OK다() {
        // 경계값: 20일 무비자 한도에 정확히 20일 체류 -> 한도를 다 채운 것이지 초과가 아니다.
        VisaRequirement req = requirement(false, 20, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), // 20일 체류
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.stayDays()).isEqualTo(20);
        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_FREE_OK);
    }

    @Test
    void 체류일수가_무비자_한도를_하루라도_넘으면_EXCEEDED다() {
        // 경계값: 19일 무비자 한도에 20일 체류 -> 하루 초과.
        VisaRequirement req = requirement(false, 19, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9), // 20일 체류
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.stayDays()).isEqualTo(20);
        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_FREE_EXCEEDED);
    }

    @Test
    void 비자_필요_국가는_VISA_REQUIRED이고_freeDays는_0() {
        VisaRequirement req = requirement(true, 0, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2028, 1, 1));

        assertThat(judgement.verdict()).isEqualTo(VisaVerdict.VISA_REQUIRED);
    }

    @Test
    void 여권_요건이_null이면_요건없음으로_간주해_passportOk는_출국일_이후_유효만_확인한다() {
        VisaRequirement req = requirement(false, 90, null);

        VisaJudgement ok = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 1, 10)); // 귀국일 하루 뒤 만료 — 요건 없으니 OK

        assertThat(ok.passportOk()).isTrue();
        assertThat(ok.passportShortfallDays()).isNull();
    }

    @Test
    void 여권_만료일이_귀국일과_정확히_같으면_귀국일_이전은_아니므로_통과한다() {
        // 경계값: LocalDate#isBefore는 같은 날짜에 false를 반환하므로, 만료일 == 귀국일은
        // "귀국일 이전 만료"가 아니다. 여권 잔여유효기간 요건이 없으면 그대로 OK.
        VisaRequirement req = requirement(false, 90, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 1, 9));

        assertThat(judgement.passportOk()).isTrue();
        assertThat(judgement.passportShortfallDays()).isNull();
    }

    @Test
    void 여권이_귀국일_이전에_만료되면_요건과_무관하게_실패한다() {
        VisaRequirement req = requirement(false, 90, null);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), LocalDate.of(2027, 1, 9),
                LocalDate.of(2027, 1, 5)); // 귀국일보다 먼저 만료

        assertThat(judgement.passportOk()).isFalse();
        assertThat(judgement.passportShortfallDays()).isEqualTo(4);
    }

    @Test
    void 여권_잔여유효기간이_요건_경계와_정확히_같으면_통과한다() {
        // 경계값: 6개월 요건 & 귀국일 이후 정확히 6개월 되는 날 만료 -> 요건을 정확히 채운 것이지
        // 미달이 아니다(isBefore는 같은 날짜에 false).
        VisaRequirement req = requirement(false, 90, 6);
        LocalDate returnDate = LocalDate.of(2027, 1, 9);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), returnDate,
                returnDate.plusMonths(6));

        assertThat(judgement.passportOk()).isTrue();
        assertThat(judgement.passportShortfallDays()).isNull();
    }

    @Test
    void 여권_잔여유효기간이_요건에_하루라도_못미치면_실패한다() {
        VisaRequirement req = requirement(false, 90, 6);
        LocalDate returnDate = LocalDate.of(2027, 1, 9);

        VisaJudgement judgement = service.judge(req,
                LocalDate.of(2026, 12, 20), returnDate,
                returnDate.plusMonths(6).minusDays(1));

        assertThat(judgement.passportOk()).isFalse();
        assertThat(judgement.passportShortfallDays()).isEqualTo(1);
    }
}
