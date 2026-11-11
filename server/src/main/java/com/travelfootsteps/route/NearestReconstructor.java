package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

// nearest: 점마다 OSRM /nearest로 가장 가까운 도로에 붙인 뒤 직선으로 잇는다. 이웃 점과의 관계를 보지 않는
// 단순한 비교 기준이다. 반경 안에 도로가 없는 점은 원래 자리에 두고, 하나도 못 붙이면(OSRM 꺼짐 등) 대체 조각이다.
class NearestReconstructor implements Reconstructor {

    // hmm_steps의 후보 반경과 같다(Newson & Krumm 2009 3.1절의 200m).
    static final double SNAP_RADIUS_M = 200;

    private final OsrmClient osrmClient;

    NearestReconstructor(OsrmClient osrmClient) {
        this.osrmClient = osrmClient;
    }

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        List<GeoPoint> coords = new ArrayList<>();
        boolean snappedAny = false;
        for (Waypoint waypoint : run) {
            Optional<GeoPoint> snapped = osrmClient.nearest(country, waypoint.point(), SNAP_RADIUS_M);
            snappedAny |= snapped.isPresent();
            coords.add(snapped.orElse(waypoint.point()));
        }
        return List.of(snappedAny ? new Piece(coords, false) : Piece.straight(run));
    }
}
