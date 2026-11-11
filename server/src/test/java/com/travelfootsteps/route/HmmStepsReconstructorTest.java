package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;

import java.util.List;

import static com.travelfootsteps.route.GridOsrm.at;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

// 격자 도로망(GridOsrm)에서 HMM이 정답 후보를 고르는지 본다. 좌표는 격자 원점에서 동쪽·북쪽 미터다.
class HmmStepsReconstructorTest {

    private static final HmmOptions BASIC = new HmmOptions(null, null, null, false);

    private static Waypoint point(long seconds, double x, double y, Double accuracy, Integer steps) {
        return new Waypoint(seconds * 1000, seconds * 1000, at(x, y), accuracy, steps, "walking");
    }

    private static void assertAt(GeoPoint p, double x, double y) {
        assertThat(GridOsrm.x(p)).isCloseTo(x, within(0.5));
        assertThat(GridOsrm.y(p)).isCloseTo(y, within(0.5));
    }

    @Test
    void 걸음_수로_실제_걸은_거리를_알아_꺾인_길의_후보를_고른다() {
        // (0,0)에서 동쪽 100m, 북쪽 40m를 걸어(140m, 187걸음) (100,40)에 있었다. 두 번째 측위는 오차 40m로
        // 블록 안 (60,40)에 찍혀 (60,0)과 (100,40)이 똑같이 40m 거리다.
        List<Waypoint> run = List.of(point(0, 0, 0, 5.0, null), point(100, 60, 40, 40.0, 187));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        Reconstructor.Piece piece = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS).get(0);

        assertThat(piece.fallback()).isFalse();
        assertAt(piece.coords().get(0), 0, 0);
        assertAt(piece.coords().get(1), 100, 0); // 모퉁이를 돌아
        assertAt(piece.coords().get(piece.coords().size() - 1), 100, 40);
    }

    @Test
    void 직선거리를_쓰는_기본_HMM은_같은_점에서_가까운_길로_잘못_간다() {
        // 직선거리(72m)는 (60,0)까지의 도로 거리(60m)와 더 가깝다 — 걸음 정보 없이는 꺾인 길을 놓친다.
        List<Waypoint> run = List.of(point(0, 0, 0, 5.0, null), point(100, 60, 40, 40.0, 187));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        Reconstructor.Piece piece = hmm.reconstruct("KR", run, BASIC).get(0);

        assertAt(piece.coords().get(piece.coords().size() - 1), 60, 0);
    }

    @Test
    void 잡음이_있어도_걷는_내내_같은_길의_후보를_고른다() {
        // y=0 길을 따라 50m(67걸음)마다 측위, 남북으로 ±20m 흔들린다. x=100·200처럼 세로 길 위에 찍힌 점도
        // 그 길로 꺾었다 돌아오는 것보다 y=0에 머무는 쪽이 걸음 수와 맞는다.
        double[] noise = {5, -12, 20, -18, 10, -15, 12};
        List<Waypoint> run = new java.util.ArrayList<>();
        for (int k = 0; k < noise.length; k++) {
            run.add(point(40L * k, 50.0 * k, noise[k], 15.0, k == 0 ? null : 67));
        }
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        List<Reconstructor.Piece> pieces = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS);

        assertThat(pieces).hasSize(1);
        assertThat(pieces.get(0).fallback()).isFalse();
        for (GeoPoint p : pieces.get(0).coords()) assertThat(GridOsrm.y(p)).isCloseTo(0, within(0.5));
        assertAt(pieces.get(0).coords().get(0), 0, 0);
        assertAt(pieces.get(0).coords().get(pieces.get(0).coords().size() - 1), 300, 0);
    }

    @Test
    void 반경_200m_안에_도로가_없는_점에서_사슬이_끊기고_그_양옆만_직선_fallback이다() {
        List<Waypoint> run = List.of(
                point(0, 0, 0, 5.0, null),
                point(80, 100, 0, 5.0, 133),
                point(160, 100, -500, 5.0, 133),   // 도로에서 500m — 후보 없음
                point(240, 200, 0, 5.0, 133),
                point(320, 300, 0, 5.0, 133));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm());

        List<Reconstructor.Piece> pieces = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS);

        assertThat(pieces).extracting(Reconstructor.Piece::fallback).containsExactly(false, true, false);
        assertThat(pieces.get(1).coords()).hasSize(3);
        assertAt(pieces.get(1).coords().get(0), 100, 0);
        assertAt(pieces.get(1).coords().get(1), 100, -500);
        assertAt(pieces.get(1).coords().get(2), 200, 0);
    }

    @Test
    void OSRM이_꺼져_있으면_받은_점을_직선으로_이은_fallback_한_조각이다() {
        List<Waypoint> run = List.of(point(0, 0, 0, 5.0, null), point(60, 60, 40, 40.0, 100));
        HmmStepsReconstructor hmm = new HmmStepsReconstructor(new GridOsrm(true));

        List<Reconstructor.Piece> pieces = hmm.reconstruct("KR", run, HmmOptions.DEFAULTS);

        assertThat(pieces).hasSize(1);
        assertThat(pieces.get(0).fallback()).isTrue();
        assertThat(pieces.get(0).coords()).containsExactly(run.get(0).point(), run.get(1).point());
    }

    @Test
    void 걸은_거리는_걸음_수와_보폭이고_걸음을_모르거나_탈것이면_직선거리다() {
        Waypoint a = point(0, 0, 0, 5.0, null);
        Waypoint walked = point(60, 60, 80, 5.0, 200);
        Waypoint vehicle = new Waypoint(60_000, 60_000, at(60, 80), 5.0, 200, "vehicle");
        Waypoint unknown = point(60, 60, 80, 5.0, null);

        assertThat(HmmStepsReconstructor.walkedDistance(a, walked, HmmOptions.DEFAULTS)).isCloseTo(150, within(1e-9));
        assertThat(HmmStepsReconstructor.walkedDistance(a, vehicle, HmmOptions.DEFAULTS)).isCloseTo(100, within(0.1));
        assertThat(HmmStepsReconstructor.walkedDistance(a, unknown, HmmOptions.DEFAULTS)).isCloseTo(100, within(0.1));
        assertThat(HmmStepsReconstructor.walkedDistance(a, walked, BASIC)).isCloseTo(100, within(0.1));
    }
}
