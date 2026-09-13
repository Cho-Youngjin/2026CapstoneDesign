package com.travelfootsteps.footsteps;

import java.time.Instant;

public record CheckinResponse(Long id, double lat, double lng, Long countryId, Instant recordedAt, String source) {
    public static CheckinResponse from(Checkin checkin) {
        return new CheckinResponse(checkin.getId(), checkin.getLat(), checkin.getLng(),
                checkin.getCountryId(), checkin.getRecordedAt(), checkin.getSource());
    }
}
