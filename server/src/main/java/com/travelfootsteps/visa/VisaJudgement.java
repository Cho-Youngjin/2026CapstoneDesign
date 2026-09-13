package com.travelfootsteps.visa;

/**
 * {@link VisaJudgementService#judge}의 판정 결과.
 *
 * @param verdict 최종 판정 (UNVERIFIED가 최우선으로 검사된다 — visaFreeDays를 모르면 다른 값은 신뢰할 수 없다).
 * @param stayDays departDate부터 returnDate까지의 체류일수.
 * @param visaFreeDays 무비자 체류 가능 일수. requirement가 없거나 파싱 실패면 null(= UNVERIFIED의 근거).
 * @param passportOk 여권이 요건(있다면)과 귀국일 이후 유효기간을 모두 만족하는지.
 * @param passportValidityMonths 여권 잔여유효기간 요건(개월). 원문에 언급이 없으면 null(= 요건 없음, UNVERIFIED와 무관).
 * @param passportShortfallDays 여권이 부족한 경우 부족한 일수. 문제 없으면 null.
 */
public record VisaJudgement(
        VisaVerdict verdict,
        int stayDays,
        Integer visaFreeDays,
        boolean passportOk,
        Integer passportValidityMonths,
        Integer passportShortfallDays
) {
}
