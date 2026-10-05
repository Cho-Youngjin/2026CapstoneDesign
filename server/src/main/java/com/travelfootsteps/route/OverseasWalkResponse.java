package com.travelfootsteps.route;

import java.util.List;

// offRoad는 앱 하위 호환용으로 항상 false다(2차 구현에서 "도로 밖 확정"을 없앴다).
// event는 "deadEnd"(막다른 길로 되돌아감) | "blocked"(갈 수 있는 길 없음) | null.
public record OverseasWalkResponse(boolean ok, boolean offRoad, List<GeoPoint> matched,
                                    GeoPoint newAnchor, String event, WalkState state) {

    public static OverseasWalkResponse failed() {
        return new OverseasWalkResponse(false, false, List.of(), null, null, null);
    }
}
