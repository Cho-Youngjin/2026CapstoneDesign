package com.travelfootsteps.footsteps;

import java.time.Instant;

public record CheckinSyncRequest(Long localId, double lat, double lng, String countryIso,
                                   Instant recordedAt, String source) {
}
