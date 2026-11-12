package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;

import java.util.List;

import static com.travelfootsteps.route.GridOsrm.at;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

// 처리 순서(머문 곳 → 공백 → 방법별 연결)와 실패 시 직선 대체를 격자 도로망 가짜 OSRM으로 본다.
class RouteReconstructionServiceTest {

    private static TrackPoint p(long seconds, double x, double y, Integer steps, String state) {
        GeoPoint g = at(x, y);
        return new TrackPoint(seconds * 1000, g.lat(), g.lng(), 5.0, steps, state);
    }

    private static TrackPoint walking(long seconds, double x, double y) {
        return p(seconds, x, y, 100, "walking");
    }

    private static ReconstructRequest request(ReconstructMethod method, List<TrackPoint> points, List<StayInput> stays) {
        return new ReconstructRequest(method, points, stays, null);
    }

    private static void assertAt(GeoPoint p, double x, double y) {
        assertThat(GridOsrm.x(p)).isCloseTo(x, within(0.5));
        assertThat(GridOsrm.y(p)).isCloseTo(y, within(0.5));
    }

    @Test
    void 머문_곳_안의_점은_중심_하나로_바뀌고_머문_시간은_공백으로_보지_않는다() {
        GeoPoint center = at(100, 0);
        List<TrackPoint> points = List.of(
                walking(0, 0, 0), walking(60, 50, 3),
                walking(200, 100, 5), walking(700, 98, 4), walking(1300, 103, 2),   // 머문 곳 안
                walking(1560, 150, 0), walking(1620, 200, 0));
        StayInput stay = new StayInput(120_000L, 1_500_000L, center.lat(), center.lng());
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        ReconstructResponse response = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of(stay)));

        RouteSegment walk = response.segments().get(0);
        assertThat(response.segments()).hasSize(1); // 23분을 머물렀어도 머문 뒤 60초 만에 다음 점이라 공백이 아니다
        assertThat(walk.kind()).isEqualTo(SegmentKind.WALK);
        assertThat(walk.coords()).hasSize(5);
        assertThat(walk.coords().get(2)).isEqualTo(center);
    }

    @Test
    void 머문_곳의_중심은_그_안에_처음_든_점의_걸음_수와_상태를_이어받는다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), p(200, 100, 5, 40, "still"), p(900, 100, 4, 0, "still"));
        StayInput stay = new StayInput(120_000L, 1_000_000L, at(100, 0).lat(), at(100, 0).lng());

        List<Waypoint> waypoints = RouteReconstructionService.waypoints(points, List.of(stay));

        assertThat(waypoints).hasSize(2);
        Waypoint center = waypoints.get(1);
        assertThat(center.startT()).isEqualTo(120_000L);
        assertThat(center.endT()).isEqualTo(1_000_000L);
        assertThat(center.stepsSincePrev()).isEqualTo(40);
        assertThat(center.state()).isEqualTo("still");
    }

    @Test
    void 십분_넘게_비면_자르고_공백_양_끝을_최단경로로_이어_estimated로_표시한다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(60, 100, 0), walking(900, 200, 100), walking(960, 300, 100));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        List<RouteSegment> segments = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments();

        assertThat(segments).extracting(RouteSegment::kind)
                .containsExactly(SegmentKind.WALK, SegmentKind.ESTIMATED, SegmentKind.WALK);
        RouteSegment gap = segments.get(1);
        assertThat(gap.fallback()).isFalse();
        assertAt(gap.coords().get(0), 100, 0);
        assertAt(gap.coords().get(gap.coords().size() - 1), 200, 100);
        assertThat(GeoMath.polylineLength(gap.coords())).isCloseTo(200, within(0.5)); // 격자 최단경로
    }

    @Test
    void 십분이_안_되는_공백은_자르지_않는다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(599, 100, 0));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        assertThat(service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments())
                .extracting(RouteSegment::kind).containsExactly(SegmentKind.WALK);
    }

    @Test
    void 공백이_정확히_십분이면_자른다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(600, 100, 0));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        assertThat(service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments())
                .extracting(RouteSegment::kind).containsExactly(SegmentKind.ESTIMATED);
    }

    @Test
    void 공백_사이에_혼자_남은_점도_양쪽_공백을_estimated로_이어_끊기지_않는다() {
        // 0초, 900초, 1800초: 점마다 10분 넘게 떨어져 도보 구간 없이 공백 두 개만 남는다.
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(900, 100, 0), walking(1800, 200, 0));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        List<RouteSegment> segments = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments();

        assertThat(segments).extracting(RouteSegment::kind).containsExactly(SegmentKind.ESTIMATED, SegmentKind.ESTIMATED);
        List<GeoPoint> first = segments.get(0).coords();
        List<GeoPoint> second = segments.get(1).coords();
        assertAt(first.get(0), 0, 0);
        assertAt(first.get(first.size() - 1), 100, 0);
        assertAt(second.get(0), 100, 0);
        assertAt(second.get(second.size() - 1), 200, 0);
    }

    @Test
    void 머문_곳_중심은_osrm_match_radius에서_반경_상한으로_보내_도로에서_떨어진_중심도_버리지_않게_한다() {
        GeoPoint a = at(0, 0);
        List<TrackPoint> points = List.of(
                new TrackPoint(0L, a.lat(), a.lng(), 5.0, null, null),
                new TrackPoint(120_000L, a.lat(), a.lng(), 5.0, null, null),   // 머문 곳 안: 중심 하나로 바뀐다
                new TrackPoint(300_000L, a.lat(), a.lng(), 8.0, null, null));
        GeoPoint c = at(0, 30);
        List<StayInput> stays = List.of(new StayInput(60_000L, 240_000L, c.lat(), c.lng()));
        GridOsrm osrm = new GridOsrm();
        RouteReconstructionService service = new RouteReconstructionService(osrm);

        service.reconstruct(request(ReconstructMethod.OSRM_MATCH_RADIUS, points, stays));

        assertThat(osrm.lastRadiuses).containsExactly(5.0, 50.0, 8.0);
    }

    @Test
    void 탈것_상태로_도착한_점까지는_vehicle_구간으로_나눈다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(60, 100, 0),
                p(120, 200, 0, null, "vehicle"), p(180, 300, 0, null, "vehicle"), walking(240, 300, 100));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        List<RouteSegment> segments = service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments();

        assertThat(segments).extracting(RouteSegment::kind)
                .containsExactly(SegmentKind.WALK, SegmentKind.VEHICLE, SegmentKind.WALK);
        assertThat(segments.get(1).coords()).hasSize(3); // 100 → 200 → 300, 경계 점은 양쪽 구간이 함께 쓴다
    }

    @Test
    void OSRM이_꺼져_있으면_방법마다_직선으로_대신하고_fallback을_붙인다() {
        List<TrackPoint> points = List.of(walking(0, 0, 0), walking(60, 60, 40), walking(900, 200, 100), walking(960, 300, 100));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm(true));

        for (ReconstructMethod method : List.of(ReconstructMethod.NEAREST, ReconstructMethod.OSRM_MATCH,
                ReconstructMethod.OSRM_MATCH_RADIUS, ReconstructMethod.HMM_STEPS)) {
            List<RouteSegment> segments = service.reconstruct(request(method, points, List.of())).segments();

            assertThat(segments).as(method.wireName()).extracting(RouteSegment::fallback).containsOnly(true);
            assertThat(segments.get(0).coords()).as(method.wireName())
                    .containsExactly(at(0, 0), at(60, 40));
            assertThat(segments.get(1).kind()).isEqualTo(SegmentKind.ESTIMATED);
            assertThat(segments.get(1).coords()).hasSize(2); // 공백도 /route 대신 직선
        }
        assertThat(service.reconstruct(request(ReconstructMethod.STRAIGHT, points, List.of())).segments().get(0)
                .fallback()).isFalse();
    }

    @Test
    void nearest는_점마다_가장_가까운_도로에_붙여_직선으로_잇는다() {
        List<TrackPoint> points = List.of(walking(0, 0, 3), walking(60, 50, 15), walking(120, 100, -4));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        RouteSegment segment = service.reconstruct(request(ReconstructMethod.NEAREST, points, List.of())).segments().get(0);

        assertThat(segment.fallback()).isFalse();
        assertAt(segment.coords().get(1), 50, 0);
    }

    @Test
    void osrm_match_radius는_정확도를_5에서_50m로_맞춘_반경과_늘어나는_초_단위_시각을_넘긴다() {
        GeoPoint a = at(0, 0);
        List<TrackPoint> points = List.of(
                new TrackPoint(1_000L, a.lat(), a.lng(), 3.0, null, null),
                new TrackPoint(1_500L, a.lat(), a.lng(), 12.5, null, null),   // 같은 초 → 1초 민다
                new TrackPoint(61_000L, a.lat(), a.lng(), 80.0, null, null),
                new TrackPoint(121_000L, a.lat(), a.lng(), null, null, null));
        GridOsrm osrm = new GridOsrm();
        RouteReconstructionService service = new RouteReconstructionService(osrm);

        service.reconstruct(request(ReconstructMethod.OSRM_MATCH_RADIUS, points, List.of()));
        assertThat(osrm.lastRadiuses).containsExactly(5.0, 12.5, 50.0, 5.0);
        assertThat(osrm.lastTimestamps).containsExactly(1L, 2L, 61L, 121L);

        service.reconstruct(request(ReconstructMethod.OSRM_MATCH, points, List.of()));
        assertThat(osrm.lastRadiuses).isNull(); // OSRM 기본값(5m)
        assertThat(osrm.lastTimestamps).isNull();
    }

    @Test
    void method를_빼면_앱_기본값_osrm_match_radius로_복원한다() {
        GridOsrm osrm = new GridOsrm();
        RouteReconstructionService service = new RouteReconstructionService(osrm);

        ReconstructResponse response = service.reconstruct(request(null, List.of(walking(0, 0, 0), walking(60, 100, 0)), null));

        assertThat(response.method()).isEqualTo(ReconstructMethod.OSRM_MATCH_RADIUS);
        assertThat(osrm.matchCalls).isEqualTo(1);
    }

    @Test
    void 점이_하나면_좌표_하나짜리_구간이고_없으면_빈_목록이다() {
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        assertThat(service.reconstruct(request(ReconstructMethod.HMM_STEPS, List.of(walking(0, 50, 0)), List.of()))
                .segments()).singleElement().satisfies(s -> assertThat(s.coords()).hasSize(1));
        assertThat(service.reconstruct(request(ReconstructMethod.HMM_STEPS, List.of(), List.of())).segments()).isEmpty();
    }

    @Test
    void 구간마다_따로_복원해_공유_점이_다르게_붙어도_앞_구간의_끝을_이어_끊기지_않는다() {
        // 걸음 187걸음으로 (100,40) 근처까지 걸어 들어온 뒤 탈것으로 돌아간다. hmm_steps는 걷는 구간의 끝을
        // (100,40)에, 탈것 구간의 시작을 (60,0)에 붙여 가운데 점에서 선이 끊긴다.
        List<TrackPoint> points = List.of(walking(0, 0, 0), p(60, 60, 40, 187, "walking"),
                p(120, 0, 0, null, "vehicle"));
        RouteReconstructionService service = new RouteReconstructionService(new GridOsrm());

        List<RouteSegment> segments = service.reconstruct(request(ReconstructMethod.HMM_STEPS, points, List.of())).segments();

        assertThat(segments).extracting(RouteSegment::kind).containsExactly(SegmentKind.WALK, SegmentKind.VEHICLE);
        for (int i = 0; i + 1 < segments.size(); i++) {
            List<GeoPoint> end = segments.get(i).coords();
            assertThat(segments.get(i + 1).coords().get(0)).isEqualTo(end.get(end.size() - 1));
        }
        assertThat(segments.get(1).fallback()).isFalse();
    }
}
