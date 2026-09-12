package com.travelfootsteps.visa;

/**
 * {@link VisaConditionParser}가 자연어 필드에서 뽑아낸 입국허가요건 파싱 결과.
 *
 * <p>{@code visaFreeDays}와 {@code passportValidityMonths}는 둘 다 {@code Integer}(null 허용)이지만
 * null이 의미하는 바가 서로 다르다 — 이 차이를 혼동하면 Task 3의 Tier 판정 로직이 잘못 동작한다.
 *
 * <ul>
 *   <li>{@code visaFreeDays == null} — "파싱 실패, 무비자 일수를 알 수 없음"이라는 뜻이다.
 *       Task 3은 이를 "Tier B 미검증 → 영사관 확인 필요" 신호로 최우선 처리한다.
 *       원문이 모호하거나 숫자를 찾을 수 없을 때는 추측하지 않고 반드시 null을 반환해야 한다.
 *   <li>{@code passportValidityMonths == null} — "원문에 여권 잔여유효기간 요건 언급이 아예 없음"이라는 뜻이다
 *       (요건이 없는 것으로 간주하며, 미검증이 아니다). 실제로 많은 나라의 문구에는 이 요건 자체가
 *       없으므로, 언급 없음을 "미검증"으로 취급하면 정상적으로 파싱된 국가 대부분이 오탐으로
 *       "영사관 확인 필요" 처리된다.
 * </ul>
 */
public record ParsedVisaCondition(
        boolean visaRequired,
        Integer visaFreeDays,
        Integer passportValidityMonths
) {
}
