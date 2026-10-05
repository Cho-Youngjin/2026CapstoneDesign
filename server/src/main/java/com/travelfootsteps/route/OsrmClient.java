package com.travelfootsteps.route;

import java.util.List;
import java.util.Optional;

// OSRM 호출을 인터페이스 뒤에 둔다 — PlacesClient와 같은 이유로, 컨트롤러/알고리즘 테스트가
// 실제 OSRM 서버 없이 이 인터페이스의 가짜 구현만으로 돌 수 있게 하기 위함이다.
//
// 모든 메서드는 OSRM이 꺼져 있거나 응답이 이상한 경우에도 예외를 던지지 않고 빈 결과
// (Optional.empty / 빈 리스트)를 돌려준다. 앱은 "실패 = ok:false"로 받아 다음 트리거에서
// 더 긴 구간으로 재시도하므로(overseas_mapping_test_page.dart), 502 같은 에러로 바꿀 이유가 없다.
public interface OsrmClient {

    /** point에서 maxDistanceMeters 안에 도로가 있으면 도로 위로 붙인 좌표를 돌려준다. */
    Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters);

    /** from에서 to까지의 경로 좌표. 경로가 없으면 빈 리스트. */
    List<GeoPoint> route(String country, GeoPoint from, GeoPoint to);

    /** 좌표열을 도로 위 경로로 재정렬(Map Matching). 실패하면 빈 리스트. */
    List<GeoPoint> match(String country, List<GeoPoint> points);
}
