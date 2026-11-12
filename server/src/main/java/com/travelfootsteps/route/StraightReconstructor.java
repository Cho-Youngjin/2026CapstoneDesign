package com.travelfootsteps.route;

import java.util.List;

// straight: 점을 직선으로 잇는다. 다른 방법과 비교하는 가장 단순한 기준선이다.
class StraightReconstructor implements Reconstructor {

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        return List.of(new Piece(Reconstructor.points(run), false));
    }
}
