package com.travelfootsteps.route;

import java.util.List;

// 복원 방법 하나(설계 6-2 표의 한 행). 공백 없이 이어진 같은 종류(도보·탈것)의 점 2개 이상을 받아 경로 조각을 낸다.
// 조각마다 fallback 여부가 다를 수 있어(예: HMM이 끊긴 곳만 직선) 목록으로 돌려준다. 실패를 예외로 알리지 않고
// 직선 조각(fallback=true)으로 돌려준다 — OsrmClient와 같은 "실패 = 빈 결과" 규칙을 응답까지 이어 간다.
interface Reconstructor {

    List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options);

    record Piece(List<GeoPoint> coords, boolean fallback) {

        /** 받은 점을 그대로 직선으로 잇는 대체 조각. */
        static Piece straight(List<Waypoint> run) {
            return new Piece(points(run), true);
        }
    }

    static List<GeoPoint> points(List<Waypoint> run) {
        return run.stream().map(Waypoint::point).toList();
    }
}
