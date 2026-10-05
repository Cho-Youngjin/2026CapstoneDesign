package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

// 가짜 OsrmClient로 알고리즘의 불변식을 검증한다. 가짜 도로망은 "어디서 어디로든 직선"이라
// OSRM 없이도 돌고, 막다른 길/끊긴 길은 route()가 빈 리스트나 짧은 경로를 주는 것으로 흉내 낸다.
class OverseasWalkServiceTest {

    private static final GeoPoint ANCHOR = new GeoPoint(35.6812, 139.7671); // 도쿄역 근처
    private static final GeoPoint KR_START = new GeoPoint(37.5547, 126.9723); // 서울역 근처

    /** 직선 도로. from→to를 그대로 돌려준다. */
    private static class StraightRoadOsrm implements OsrmClient {
        @Override
        public Optional<GeoPoint> nearest(String country, GeoPoint point, double max) {
            return Optional.of(point);
        }

        @Override
        public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
            return List.of(from, to);
        }

        @Override
        public List<GeoPoint> match(String country, List<GeoPoint> points) {
            return points;
        }
    }

    private static List<GeoPoint> krWalkNorth(double meters) {
        return List.of(KR_START, GeoMath.destination(KR_START, 0, meters));
    }

    @Test
    void 한국에서_걸은_거리만큼_도로를_따라_걷고_첫점은_anchor다() {
        OverseasWalkService service = new OverseasWalkService(new StraightRoadOsrm());

        OverseasWalkResponse response = service.walk("JP", ANCHOR, krWalkNorth(50), null);

        assertThat(response.ok()).isTrue();
        assertThat(response.event()).isNull();
        assertThat(response.matched().get(0)).isEqualTo(ANCHOR);
        assertThat(GeoMath.polylineLength(response.matched())).isBetween(49.0, 51.0);
        assertThat(response.newAnchor()).isEqualTo(response.matched().get(response.matched().size() - 1));
    }

    @Test
    void 첫_요청의_진행방향은_한국_이동방향을_따른다() {
        OverseasWalkService service = new OverseasWalkService(new StraightRoadOsrm());

        OverseasWalkResponse response = service.walk("JP", ANCHOR, krWalkNorth(50), null);

        // 한국에서 정북(0°)으로 걸었으니 해외도 정북 근처여야 한다.
        assertThat(GeoMath.angleDiff(response.state().heading(), 0)).isLessThan(2);
        assertThat(response.state().krHeading()).isBetween(-1.0, 1.0);
        assertThat(response.state().trail()).isNotEmpty();
    }

    @Test
    void state를_다음_요청에_넘기면_이어서_걷는다() {
        OverseasWalkService service = new OverseasWalkService(new StraightRoadOsrm());

        OverseasWalkResponse first = service.walk("JP", ANCHOR, krWalkNorth(50), null);
        GeoPoint krNext = GeoMath.destination(KR_START, 0, 50);
        OverseasWalkResponse second = service.walk("JP", first.newAnchor(),
                List.of(krNext, GeoMath.destination(krNext, 0, 50)), first.state());

        assertThat(second.ok()).isTrue();
        assertThat(second.matched().get(0)).isEqualTo(first.newAnchor());
        // 일직선으로 계속 걸었으니 진행 방향이 유지되고, 이상 위치도 앞으로 계속 전진한다.
        assertThat(GeoMath.angleDiff(second.state().heading(), first.state().heading())).isLessThan(2);
        assertThat(GeoMath.haversine(second.state().ideal(), first.state().ideal())).isBetween(49.0, 51.0);
    }

    @Test
    void 갈_수_있는_길이_없으면_blocked로_제자리에_머문다() {
        OsrmClient noRoad = new StraightRoadOsrm() {
            @Override
            public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
                return List.of();
            }
        };

        OverseasWalkResponse response = new OverseasWalkService(noRoad).walk("JP", ANCHOR, krWalkNorth(50), null);

        assertThat(response.ok()).isTrue();
        assertThat(response.event()).isEqualTo("blocked");
        assertThat(response.matched()).containsExactly(ANCHOR);
        assertThat(response.newAnchor()).isEqualTo(ANCHOR);
    }

    @Test
    void 앞쪽이_막다른_길이면_deadEnd로_되돌아가는_길을_택한다() {
        // 북쪽(앞)으로는 5m 전진하면 끝나는 막다른 길, 남쪽(뒤)으로는 계속 이어지는 길.
        OsrmClient deadEndAhead = new StraightRoadOsrm() {
            @Override
            public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
                double bearing = GeoMath.bearingDeg(from, to);
                if (GeoMath.angleDiff(bearing, 0) <= 100) {
                    return List.of(from, GeoMath.destination(from, Math.toRadians(bearing), 5));
                }
                return List.of(from, to);
            }
        };

        OverseasWalkResponse response = new OverseasWalkService(deadEndAhead)
                .walk("JP", ANCHOR, krWalkNorth(50), null);

        assertThat(response.ok()).isTrue();
        assertThat(response.event()).isEqualTo("deadEnd");
        assertThat(GeoMath.polylineLength(response.matched())).isGreaterThan(40);
        // deadEnd에서는 지나온 길 기록을 비운다(되돌아간 길과 겹쳐 또 막히지 않도록).
        assertThat(response.state().trail().size()).isLessThan(20);
    }

    @Test
    void 이동이_없으면_실패한다() {
        OverseasWalkService service = new OverseasWalkService(new StraightRoadOsrm());

        assertThat(service.walk("JP", ANCHOR, List.of(KR_START), null).ok()).isFalse();
        assertThat(service.walk("JP", ANCHOR, List.of(KR_START, KR_START), null).ok()).isFalse();
    }
}
