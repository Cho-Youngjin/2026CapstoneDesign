package com.travelfootsteps.visa;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

/**
 * 스펙 §6-①의 판정 로직을 그대로 구현한다. 이 클래스는 Spring 빈이 아니다 — DB에도, HTTP에도
 * 접근하지 않는 순수 도메인 로직이라 스프링 없이 바로 단위 테스트로 검증할 수 있다. 어떤
 * {@link VisaRequirement}를 넘길지는 호출부(Task 6의 TripController)가 리포지토리에서 조회해
 * 정한다 — 이 서비스는 리포지토리를 주입받지 않는다.
 */
public class VisaJudgementService {

    public VisaJudgement judge(VisaRequirement requirement, LocalDate departDate,
                                LocalDate returnDate, LocalDate passportExpiry) {
        int stayDays = (int) ChronoUnit.DAYS.between(departDate, returnDate);

        Integer visaFreeDays = requirement != null ? requirement.getVisaFreeDays() : null;
        VisaVerdict verdict = determineVerdict(requirement, stayDays, visaFreeDays);

        Integer passportValidityMonths = requirement != null ? requirement.getPassportValidityMonths() : null;
        PassportCheck passportCheck = checkPassport(returnDate, passportExpiry, passportValidityMonths);

        return new VisaJudgement(verdict, stayDays, visaFreeDays,
                passportCheck.ok(), passportValidityMonths, passportCheck.shortfallDays());
    }

    private VisaVerdict determineVerdict(VisaRequirement requirement, int stayDays, Integer visaFreeDays) {
        // 최우선 규칙: requirement 자체가 없거나(아직 수집 안 됨) visaFreeDays를 모르면(파싱 실패)
        // 다른 어떤 조건도 검사하지 않고 무조건 UNVERIFIED다. 검증되지 않은 값으로 "무비자 OK"라고
        // 잘못 안내하는 것이, 보수적으로 "영사관 확인 필요"라고 안내하는 것보다 훨씬 나쁘다.
        if (requirement == null || visaFreeDays == null) {
            return VisaVerdict.UNVERIFIED;
        }
        // 체류일수가 무비자 한도 "이내"인지 검사한다. N일 무비자는 관례상 N일째까지 체류 가능하다는
        // 뜻이므로 stayDays == visaFreeDays(한도를 꽉 채운 경우)는 초과가 아니라 OK다 — 그래서 `<=`.
        if (!requirement.isVisaRequired() && stayDays <= visaFreeDays) {
            return VisaVerdict.VISA_FREE_OK;
        }
        if (!requirement.isVisaRequired()) {
            return VisaVerdict.VISA_FREE_EXCEEDED;
        }
        return VisaVerdict.VISA_REQUIRED;
    }

    private PassportCheck checkPassport(LocalDate returnDate, LocalDate passportExpiry, Integer requiredMonths) {
        // 여권 요건과 무관하게 지켜야 하는 최소 조건: 여권이 귀국일보다 먼저 만료되면 안 된다.
        if (passportExpiry.isBefore(returnDate)) {
            long shortfall = ChronoUnit.DAYS.between(passportExpiry, returnDate);
            return new PassportCheck(false, (int) shortfall);
        }
        // requiredMonths == null은 "원문에 여권 잔여유효기간 요건 언급이 아예 없음"이라는 뜻이다
        // (요건 없음으로 간주 — UNVERIFIED와는 무관하다). 위의 귀국일 이후 유효 조건만 통과하면 OK.
        if (requiredMonths == null) {
            return new PassportCheck(true, null);
        }
        LocalDate requiredMinExpiry = returnDate.plusMonths(requiredMonths);
        if (passportExpiry.isBefore(requiredMinExpiry)) {
            long shortfall = ChronoUnit.DAYS.between(passportExpiry, requiredMinExpiry);
            return new PassportCheck(false, (int) shortfall);
        }
        return new PassportCheck(true, null);
    }

    private record PassportCheck(boolean ok, Integer shortfallDays) {
    }
}
