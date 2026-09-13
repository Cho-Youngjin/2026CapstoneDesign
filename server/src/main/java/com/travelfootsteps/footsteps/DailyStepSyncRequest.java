package com.travelfootsteps.footsteps;

import java.time.LocalDate;

public record DailyStepSyncRequest(Long localId, LocalDate date, String countryIso, int stepCount) {
}
