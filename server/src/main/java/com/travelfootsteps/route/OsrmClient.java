package com.travelfootsteps.route;

import java.util.List;
import java.util.Optional;

// OSRM 호출을 인터페이스 뒤에 둔다 — PlacesClient와 같은 이유로, 컨트롤러/알고리즘 테스트가
// 실제 OSRM 서버 없이 이 인터페이스의 가짜 구현만으로 돌 수 있게 하기 위함이다.
//
// 모든 메서드는 OSRM이 꺼져 있거나 응답이 이상한 경우에도 예외를 던지지 않고 빈 결과
// (Optional.empty / 빈 리스트)를 돌려준다. 앱은 "실패 = ok:false"로 받아 다음 트리거에서
// 더 긴 구간으로 재시도하므로(overseas_mapping_page.dart), 502 같은 에러로 바꿀 이유가 없다.
//
// 아래쪽 세 메서드(경로 복원용, 설계 2026-11-07 6장)는 default 메서드다. default는 자바 문법으로,
// 인터페이스가 기본 구현을 갖게 해 이미 이 인터페이스를 구현한 클래스(테스트용 StubOsrmClient 등)를
// 고치지 않아도 컴파일되게 한다. 기본 구현은 "지원 안 함 = 빈 결과"라서 위의 실패 규칙과 같고,
// 경로 복원은 빈 결과를 받으면 직선으로 대신 채운다. 진짜 구현은 HttpOsrmClient가 덮어쓴다.
public interface OsrmClient {

    /** point에서 maxDistanceMeters 안에 도로가 있으면 도로 위로 붙인 좌표를 돌려준다. */
    Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters);

    /** from에서 to까지의 경로 좌표. 경로가 없으면 빈 리스트. */
    List<GeoPoint> route(String country, GeoPoint from, GeoPoint to);

    /** 좌표열을 도로 위 경로로 재정렬(Map Matching). 실패하면 빈 리스트. */
    List<GeoPoint> match(String country, List<GeoPoint> points);

    /**
     * point에서 가까운 도로 위 점을 가까운 순으로 최대 number개(OSRM /nearest?number=N). maxDistanceMeters보다
     * 먼 점은 뺀다. OSRM은 양방향 도로의 두 방향을 같은 위치로 두 번 줄 수 있다. 실패하면 빈 리스트.
     */
    default List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters) {
        return List.of();
    }

    /**
     * sources[i]에서 destinations[j]까지 도로 경로 거리(m) 표(OSRM /table, annotations=distance).
     * 길이 없는 칸은 null이고, 호출이 실패하면 빈 리스트다.
     */
    default List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations) {
        return List.of();
    }

    /**
     * 점마다 GPS 표준편차(radiuses, m)와 시각(timestamps, 초)을 함께 넘기는 Map Matching. 둘 다 points와 길이가
     * 같아야 하고, null이면 그 옵션을 보내지 않는다(OSRM 기본 반경 5m). 시각은 앞 점보다 커야 한다 — OSRM은
     * 늘어나는 시각만 받는다. 실패하면(잘못된 반경 포함) 빈 리스트.
     */
    default List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps) {
        return List.of();
    }
}
