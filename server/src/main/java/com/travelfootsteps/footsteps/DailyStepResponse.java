package com.travelfootsteps.footsteps;

import java.time.LocalDate;

// countryId(내부 PK)가 아니라 countryIso를 돌려준다 — 클라이언트는 국가 코드만 알고 내부 PK는
// 모르므로, PK를 그대로 내려주면 다기기 복원 시 국가 정보를 되돌릴 방법이 없다(리뷰 반영).
public record DailyStepResponse(Long id, LocalDate date, String countryIso, int stepCount) {
    public static DailyStepResponse from(DailyStep dailyStep, String countryIso) {
        return new DailyStepResponse(dailyStep.getId(), dailyStep.getDate(),
                countryIso, dailyStep.getStepCount());
    }
}
