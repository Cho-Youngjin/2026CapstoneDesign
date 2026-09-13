package com.travelfootsteps.footsteps;

import java.time.LocalDate;

public record DailyStepResponse(Long id, LocalDate date, Long countryId, int stepCount) {
    public static DailyStepResponse from(DailyStep dailyStep) {
        return new DailyStepResponse(dailyStep.getId(), dailyStep.getDate(),
                dailyStep.getCountryId(), dailyStep.getStepCount());
    }
}
