package com.travelfootsteps.footsteps;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

import java.time.Instant;

public record CheckinSyncRequest(
        Long localId,
        double lat,
        double lng,
        @NotBlank String countryIso,
        @NotNull Instant recordedAt,
        @NotBlank @Pattern(regexp = "AUTO|MANUAL|IMPORT") String source
) {
}
