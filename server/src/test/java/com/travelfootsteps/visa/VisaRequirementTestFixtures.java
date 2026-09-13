package com.travelfootsteps.visa;

import java.time.OffsetDateTime;

/**
 * 다른 패키지의 테스트(예: {@code com.travelfootsteps.trip.TripControllerTest})가 판정 필드를
 * 채운 {@link VisaRequirement} 픽스처를 만들 때 쓰는 공개 헬퍼다.
 *
 * <p>{@link VisaRequirement#applyCollectedData}는 (Task 3의 설계상) 의도적으로 패키지
 * 프라이빗이다 — 판정 필드(visaRequired/visaFreeDays/passportValidityMonths)를 바꾸는 통로를
 * {@code VisaRequirementCollector}로 좁혀서, 다른 패키지가 검증 없이 그 값을 직접 덮어쓰는 일을
 * 막기 위해서다. 이 클래스는 같은 패키지({@code com.travelfootsteps.visa})에 있어서 그 메서드를
 * 대신 호출해줄 수 있고, 테스트 전용 코드이므로 원래 설계 의도(운영 코드에서의 접근 제한)를
 * 해치지 않는다.
 */
public class VisaRequirementTestFixtures {

    /** 새 VisaRequirement 행을 만들고 바로 판정 결과를 채운다(아직 DB에 저장하지 않은 상태). */
    public static VisaRequirement create(Long countryId, boolean visaRequired, Integer visaFreeDays,
                                          Integer passportValidityMonths, String rawText,
                                          OffsetDateTime sourceFetchedAt) {
        VisaRequirement requirement = VisaRequirement.newUnverified(countryId, "GENERAL");
        applyCollectedData(requirement, visaRequired, visaFreeDays, passportValidityMonths,
                rawText, sourceFetchedAt);
        return requirement;
    }

    /** 이미 존재하는 행을 새 판정 결과로 갱신한다 — 실제 배치 재수집을 흉내낸다. */
    public static void applyCollectedData(VisaRequirement requirement, boolean visaRequired,
                                           Integer visaFreeDays, Integer passportValidityMonths,
                                           String rawText, OffsetDateTime sourceFetchedAt) {
        requirement.applyCollectedData(
                new ParsedVisaCondition(visaRequired, visaFreeDays, passportValidityMonths),
                rawText, null, null, sourceFetchedAt);
    }

    private VisaRequirementTestFixtures() {
    }
}
