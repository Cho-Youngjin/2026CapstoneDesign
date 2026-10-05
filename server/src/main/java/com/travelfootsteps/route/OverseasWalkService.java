package com.travelfootsteps.route;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import static com.travelfootsteps.route.GeoMath.angleDiff;
import static com.travelfootsteps.route.GeoMath.bearingDeg;
import static com.travelfootsteps.route.GeoMath.destination;
import static com.travelfootsteps.route.GeoMath.haversine;
import static com.travelfootsteps.route.GeoMath.polylineLength;
import static com.travelfootsteps.route.GeoMath.resample;
import static com.travelfootsteps.route.GeoMath.wrap180;

/**
 * 해외 도로 위 걷기. mock-server/mock_server.py의 walk_overseas_segment와 그 도움 함수를
 * 옮긴 것이다(알고리즘 배경과 가중치 선정 근거는 docs/superpowers/specs/2026-09-30-korea-overseas-mapping-report.md).
 *
 * 합성 좌표를 매번 가장 가까운 도로에 붙이면 갈림길에서 좌우를 오가고 막다른 길에서 멈춘다.
 * 그래서 해외 위치를 "항상 도로 위 점"으로 두고, 한국에서 걸은 거리(d)만큼 도로를 따라
 * 걷는다. 방향은 한국의 절대 방위가 아니라 회전량(좌/우로 몇 도 꺾었나)을 해외 쪽 마지막
 * 진행 방향에 더해 정한다.
 */
@Service
@RequiredArgsConstructor
public class OverseasWalkService {

    private static final double[] OFFSETS = {0, 45, -45, 90, -90, 135, -135, 180}; // 원하는 방향 기준 후보 각도
    private static final double W_ANGLE = 1.0;   // 원하는 방향과 실제 진행 방향의 차이(0~1로 정규화)
    private static final double W_SHORT = 2.0;   // d보다 적게 전진한 비율
    private static final double W_BACK = 1.5;    // 최근 지나온 길과 겹친 비율
    private static final double W_SIDE = 0.05;   // 동점일 때 직전에 꺾은 쪽을 우선하는 가중
    // 한국 이동을 그대로 옮겼다면 도착했을 "이상 위치"와 후보 끝점 사이 거리(0~1.5로 제한).
    // 도로가 꺾이는 대로만 따라가면 한국의 절대 방향에서 계속 벗어나므로, 갈림길에서 이상
    // 위치 쪽으로 복귀하게 하는 힘이다.
    private static final double W_IDEAL = 3.0;
    private static final double IDEAL_SCALE_M = 200.0;
    private static final double TURN_DEADBAND_DEG = 10;   // 이보다 작은 한국 회전량은 GPS 흔들림으로 보고 무시
    private static final double FORWARD_MAX_ANGLE = 100;  // 이 각도 이내면 "앞으로 가는" 후보
    private static final double FORWARD_MIN_ADVANCE = 0.5; // 앞으로 가는 후보가 d의 이 비율 이상 전진해야 함
    private static final double BACK_RADIUS_M = 6;
    // 경로 끝이 교차로에서 꺾여 이 길이(m)보다 짧게 남으면 그 꺾인 조각은 잘라낸다.
    // d미터에서 자르다 보면 옆 갈래 안쪽 몇 m에 서게 되고, 다음 요청이 거기서 되돌아나온다.
    private static final double SPUR_MAX_M = 15;
    private static final double SPUR_TURN_DEG = 60;
    private static final int TRAIL_POINTS = 40;           // 5m 간격으로 약 200m

    private final OsrmClient osrmClient;

    private record Candidate(double offset, List<GeoPoint> path, double advance,
                             double angle, double overlap, double idealErr) {
    }

    /**
     * anchor(도로 위 점)에서 krPoints의 이동 거리만큼 해외 도로를 따라 걷는다.
     * 지원하지 않는 국가이거나 이동이 없으면(점이 2개 미만, 거리 0) ok=false를 돌려준다.
     */
    public OverseasWalkResponse walk(String country, GeoPoint anchor, List<GeoPoint> krPoints, WalkState prev) {
        if (anchor == null || krPoints.size() < 2) return OverseasWalkResponse.failed();

        double d = polylineLength(krPoints);
        if (d == 0) return OverseasWalkResponse.failed();

        WalkState state = prev != null ? prev : new WalkState(null, null, null, null, null);
        double krHeading = bearingDeg(krPoints.get(0), krPoints.get(krPoints.size() - 1));
        Double heading = state.heading();

        double desired;
        if (heading == null) {
            desired = krHeading;
        } else {
            double delta = state.krHeading() != null ? wrap180(krHeading - state.krHeading()) : 0.0;
            if (Math.abs(delta) < TURN_DEADBAND_DEG) delta = 0.0;
            desired = GeoMath.mod(heading + delta, 360);
        }

        List<GeoPoint> trail = state.trail() != null ? state.trail() : List.of();
        // 파이썬 원본의 `or 1`과 같게, null뿐 아니라 0도 +1로 취급한다.
        int turnSide = state.turnSide() == null || state.turnSide() == 0 ? 1 : state.turnSide();
        GeoPoint ideal = destination(state.ideal() != null ? state.ideal() : anchor, Math.toRadians(krHeading), d);

        List<Candidate> candidates = new ArrayList<>();
        for (double offset : OFFSETS) {
            GeoPoint target = destination(anchor, Math.toRadians(desired + offset), d);
            List<GeoPoint> route = osrmClient.route(country, anchor, target);
            if (route.isEmpty()) continue;

            GeoMath.Truncated truncated = GeoMath.truncate(route, d);
            List<GeoPoint> path = new ArrayList<>();
            path.add(anchor);
            // 경로 시작이 anchor와 15m 안이면 그 점을 anchor로 대체하고, 멀면 anchor를 앞에 덧붙인다.
            List<GeoPoint> rest = truncated.path();
            path.addAll(haversine(rest.get(0), anchor) < 15 ? rest.subList(1, rest.size()) : rest);

            Double chord = truncated.advance() >= 5 ? bearingDeg(path.get(0), path.get(path.size() - 1)) : null;
            candidates.add(new Candidate(offset, path, truncated.advance(),
                    chord == null ? 180.0 : angleDiff(chord, desired),
                    overlapFraction(path, trail),
                    haversine(path.get(path.size() - 1), ideal)));
        }

        if (candidates.isEmpty()) {
            WalkState next = new WalkState(heading, krHeading, trail, turnSide, ideal);
            return new OverseasWalkResponse(true, false, List.of(anchor), anchor, "blocked", next);
        }

        List<Candidate> forward = candidates.stream()
                .filter(c -> c.angle() <= FORWARD_MAX_ANGLE
                        && c.advance() >= FORWARD_MIN_ADVANCE * d
                        && c.overlap() < 0.5)
                .toList();

        String event = null;
        Candidate chosen;
        if (!forward.isEmpty()) {
            int side = turnSide;
            chosen = forward.stream()
                    .min(Comparator.comparingDouble(c -> score(c, side, d)))
                    .orElseThrow();
        } else {
            // 앞으로 갈 길이 없다(막다른 길): 되돌아가는 쪽 중 가장 멀리 가는 후보를 택한다.
            event = "deadEnd";
            List<Candidate> backward = candidates.stream().filter(c -> c.angle() > FORWARD_MAX_ANGLE).toList();
            chosen = (backward.isEmpty() ? candidates : backward).stream()
                    .max(Comparator.comparingDouble(Candidate::advance))
                    .orElseThrow();
        }

        List<GeoPoint> path = trimTrailingSpur(chosen.path(), d);
        Double newHeading = endHeading(path);
        if (chosen.offset() != 0) turnSide = chosen.offset() > 0 ? 1 : -1;

        List<GeoPoint> newTrail = new ArrayList<>("deadEnd".equals(event) ? List.of() : trail);
        newTrail.addAll(resample(path, 5.0));
        if (newTrail.size() > TRAIL_POINTS) newTrail = new ArrayList<>(newTrail.subList(newTrail.size() - TRAIL_POINTS, newTrail.size()));

        WalkState next = new WalkState(newHeading != null ? newHeading : heading, krHeading, newTrail, turnSide, ideal);
        return new OverseasWalkResponse(true, false, path, path.get(path.size() - 1), event, next);
    }

    // 낮을수록 좋다. 동점일 때는 직전에 꺾은 쪽(turnSide)으로 살짝 쏠리게 한다.
    private static double score(Candidate c, int turnSide, double d) {
        double sideBonus = c.offset() * turnSide > 0 ? W_SIDE : 0.0;
        return W_ANGLE * c.angle() / 180
                + W_SHORT * Math.max(0.0, 1 - c.advance() / d)
                + W_BACK * c.overlap()
                + W_IDEAL * Math.min(c.idealErr() / IDEAL_SCALE_M, 1.5)
                - sideBonus;
    }

    /** path 중 (시작 10m 제외) trail과 겹치는 비율. 지나온 길로 되돌아가는지 본다. */
    private static double overlapFraction(List<GeoPoint> path, List<GeoPoint> trail) {
        if (trail.isEmpty()) return 0.0;
        List<GeoPoint> resampled = resample(path, 5.0);
        List<GeoPoint> sampled = resampled.size() > 2 ? resampled.subList(2, resampled.size()) : List.of();
        if (sampled.isEmpty()) return 0.0;
        long hits = sampled.stream()
                .filter(p -> trail.stream().anyMatch(q -> haversine(p, q) <= BACK_RADIUS_M))
                .count();
        return (double) hits / sampled.size();
    }

    /** 경로 끝 span미터 구간의 진행 방향(도). 너무 짧으면 null. */
    private static Double endHeading(List<GeoPoint> path) {
        double span = 15.0;
        double acc = 0;
        for (int i = path.size() - 1; i > 0; i--) {
            acc += haversine(path.get(i - 1), path.get(i));
            if (acc >= span || i == 1) {
                if (acc < 3) return null;
                return bearingDeg(path.get(i - 1), path.get(path.size() - 1));
            }
        }
        return null;
    }

    /**
     * 경로 끝의 꺾인 짧은 조각(교차로 옆 갈래 안쪽)을 잘라 교차로에서 끝내게 한다.
     * 잘라낸 뒤 d의 절반도 안 남으면 자르지 않는다.
     */
    private static List<GeoPoint> trimTrailingSpur(List<GeoPoint> path, double d) {
        List<GeoPoint> pts = new ArrayList<>();
        pts.add(path.get(0));
        for (GeoPoint p : path.subList(1, path.size())) {
            if (haversine(pts.get(pts.size() - 1), p) >= 1.0) pts.add(p);
        }
        for (int i = pts.size() - 2; i > 0; i--) {
            double turn = angleDiff(bearingDeg(pts.get(i - 1), pts.get(i)), bearingDeg(pts.get(i), pts.get(i + 1)));
            if (turn >= SPUR_TURN_DEG) {
                double tail = polylineLength(pts.subList(i, pts.size()));
                double head = polylineLength(pts.subList(0, i + 1));
                if (tail < SPUR_MAX_M && head >= 0.5 * d) return new ArrayList<>(pts.subList(0, i + 1));
                return path;
            }
        }
        return path;
    }
}
