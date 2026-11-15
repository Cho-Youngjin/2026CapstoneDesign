package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;

// osrm_match / osrm_match_radius: OSRM /match(OSRM 자체의 Newson & Krumm식 HMM)로 잇는다.
//  - withRadius=false(osrm_match): OSRM 기본값(GPS 표준편차 5m)만 쓴다.
//  - withRadius=true(osrm_match_radius, 앱 기본값): 점마다 정확도를 5~50m로 맞춘 radiuses와 시각(timestamps)을 넘긴다.
// 실패(빈 결과)하면 직선 대체 조각이다.
class OsrmMatchReconstructor implements Reconstructor {

    static final double MIN_RADIUS_M = 5;
    static final double MAX_RADIUS_M = 50;

    private final OsrmClient osrmClient;
    private final boolean withRadius;

    OsrmMatchReconstructor(OsrmClient osrmClient, boolean withRadius) {
        this.osrmClient = osrmClient;
        this.withRadius = withRadius;
    }

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        List<GeoPoint> points = Reconstructor.points(run);
        List<GeoPoint> matched = withRadius
                ? osrmClient.match(country, points, radiuses(run), timestamps(run))
                : osrmClient.match(country, points, null, null);
        return List.of(matched.isEmpty() ? Piece.straight(run) : new Piece(matched, false));
    }

    // 정확도를 모르면 OSRM 기본값(5m)으로 본다. 50m보다 크게 주면 엉뚱한 먼 도로까지 후보가 된다(검색 반경은 3배).
    static List<Double> radiuses(List<Waypoint> run) {
        return run.stream()
                .map(w -> w.accuracy() == null ? MIN_RADIUS_M
                        : Math.max(MIN_RADIUS_M, Math.min(MAX_RADIUS_M, w.accuracy())))
                .toList();
    }

    // OSRM은 초 단위 시각이 늘어나기만 해야 한다. 1초 안에 찍힌 점이 같은 초가 되지 않게 1초씩 밀어 준다.
    // 머문 곳은 도착 시각을 쓴다.
    static List<Long> timestamps(List<Waypoint> run) {
        List<Long> out = new ArrayList<>();
        long previous = Long.MIN_VALUE;
        for (Waypoint waypoint : run) {
            long seconds = Math.floorDiv(waypoint.startT(), 1000L);
            if (previous != Long.MIN_VALUE && seconds <= previous) seconds = previous + 1;
            out.add(seconds);
            previous = seconds;
        }
        return out;
    }
}
