package com.travelfootsteps.route;

import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * 드문 측위 점과 머문 곳으로 하루 경로를 복원한다(설계 2026-11-07 6장, 모듈 C-2).
 *
 * <p>@Service: 스프링이 시작할 때 이 클래스의 객체를 하나 만들어(빈) 컨테이너에 넣고, 필요한 곳(ReconstructController)에
 * 넣어 준다. 생성자가 하나뿐이면 스프링이 그 생성자의 파라미터(OsrmClient)에 맞는 빈을 찾아 자동으로 넘긴다 —
 * 실행 중에는 HttpOsrmClient, test 프로필에서는 StubOsrmClient다. 방법별 Reconstructor는 이 서비스만 쓰는 보통
 * 객체라 빈으로 만들지 않고 여기서 직접 만든다. 그래서 테스트는 가짜 OsrmClient 하나로 서비스 전체를 만든다.
 *
 * <p>처리 순서(설계 6-2):
 * <ol>
 *   <li>머문 곳 시간 범위 안의 점을 그 머문 곳 중심 하나로 바꾼다.</li>
 *   <li>10분 이상의 공백(측위 실패·걸음 없는 이동)에서 자르고, 공백 양 끝은 /route로 이어 estimated로 표시한다.</li>
 *   <li>남은 구간을 도보·탈것으로 나눠 요청한 방법으로 잇는다. 실패한 조각은 직선 + fallback이다.</li>
 * </ol>
 */
@Service
public class RouteReconstructionService {

    // 대상 국가는 KR 고정이다(설계 6-1). 해외 이동은 연구 범위 밖이다.
    static final String COUNTRY = "KR";
    static final long GAP_MS = 10 * 60 * 1000L;

    private final OsrmClient osrmClient;
    private final Map<ReconstructMethod, Reconstructor> reconstructors = new EnumMap<>(ReconstructMethod.class);

    public RouteReconstructionService(OsrmClient osrmClient) {
        this.osrmClient = osrmClient;
        reconstructors.put(ReconstructMethod.STRAIGHT, new StraightReconstructor());
        reconstructors.put(ReconstructMethod.NEAREST, new NearestReconstructor(osrmClient));
        reconstructors.put(ReconstructMethod.OSRM_MATCH, new OsrmMatchReconstructor(osrmClient, false));
        reconstructors.put(ReconstructMethod.OSRM_MATCH_RADIUS, new OsrmMatchReconstructor(osrmClient, true));
        reconstructors.put(ReconstructMethod.HMM_STEPS, new HmmStepsReconstructor(osrmClient));
    }

    public ReconstructResponse reconstruct(ReconstructRequest request) {
        ReconstructMethod method = request.method() != null ? request.method() : ReconstructMethod.OSRM_MATCH_RADIUS;
        HmmOptions options = HmmOptions.orDefaults(request.hmm());
        List<Waypoint> waypoints = waypoints(request.points(), request.stays() != null ? request.stays() : List.of());

        List<RouteSegment> segments = new ArrayList<>();
        if (waypoints.size() == 1) {
            // 점 하나뿐인 날도 어디 있었는지는 보여 줄 수 있게 좌표 하나짜리 구간으로 돌려준다.
            segments.add(new RouteSegment(SegmentKind.WALK, List.of(waypoints.get(0).point()), false));
            return new ReconstructResponse(method, segments);
        }

        GeoPoint previousEnd = null;
        for (List<Waypoint> run : splitAtGaps(waypoints)) {
            List<RouteSegment> runSegments = reconstructRun(method, run, options);
            GeoPoint start = runSegments.isEmpty() ? run.get(0).point() : runSegments.get(0).coords().get(0);
            if (previousEnd != null) segments.add(estimated(previousEnd, start));
            segments.addAll(runSegments);
            previousEnd = runSegments.isEmpty() ? run.get(run.size() - 1).point() : lastCoord(runSegments);
        }
        return new ReconstructResponse(method, segments);
    }

    /** 1단계: 점을 시각순으로 놓고, 머문 곳 범위 안의 점은 빼고 머문 곳마다 중심 하나를 넣는다. */
    static List<Waypoint> waypoints(List<TrackPoint> points, List<StayInput> stays) {
        List<StayInput> sortedStays = stays.stream().sorted(Comparator.comparing(StayInput::arrive)).toList();
        // 머문 곳에 처음 든 점. 머문 곳 중심이 그 점의 '직전 이후 걸음 수'와 상태를 이어받는다(걸어 들어온 몫).
        TrackPoint[] firstInside = new TrackPoint[sortedStays.size()];

        List<Waypoint> out = new ArrayList<>();
        for (TrackPoint p : points.stream().sorted(Comparator.comparing(TrackPoint::t)).toList()) {
            int stay = stayContaining(sortedStays, p.t());
            if (stay < 0) {
                out.add(new Waypoint(p.t(), p.t(), new GeoPoint(p.lat(), p.lng()),
                        p.accuracy(), p.stepsSincePrev(), p.state()));
            } else if (firstInside[stay] == null) {
                firstInside[stay] = p;
            }
        }
        for (int k = 0; k < sortedStays.size(); k++) {
            StayInput s = sortedStays.get(k);
            TrackPoint first = firstInside[k];
            out.add(new Waypoint(s.arrive(), s.leave(), new GeoPoint(s.lat(), s.lng()), null,
                    first == null ? null : first.stepsSincePrev(), first == null ? null : first.state()));
        }
        // List.sort는 안정 정렬이라 시각이 같으면 넣은 순서(측위 점, 머문 곳)를 지킨다.
        out.sort(Comparator.comparingLong(Waypoint::startT));
        return out;
    }

    private static int stayContaining(List<StayInput> stays, long t) {
        for (int k = 0; k < stays.size(); k++) {
            if (stays.get(k).arrive() <= t && t <= stays.get(k).leave()) return k;
        }
        return -1;
    }

    /** 2단계: 앞 점이 끝난 뒤 다음 점까지 10분 이상 비면 자른다. */
    static List<List<Waypoint>> splitAtGaps(List<Waypoint> waypoints) {
        List<List<Waypoint>> runs = new ArrayList<>();
        List<Waypoint> current = new ArrayList<>();
        for (Waypoint w : waypoints) {
            if (!current.isEmpty() && w.startT() - current.get(current.size() - 1).endT() >= GAP_MS) {
                runs.add(current);
                current = new ArrayList<>();
            }
            current.add(w);
        }
        if (!current.isEmpty()) runs.add(current);
        return runs;
    }

    /** 3단계: 한 덩어리를 도보·탈것으로 나눠 잇는다. 점 사이의 종류는 도착하는 점의 상태로 정한다. */
    private List<RouteSegment> reconstructRun(ReconstructMethod method, List<Waypoint> run, HmmOptions options) {
        Reconstructor reconstructor = reconstructors.get(method);
        List<RouteSegment> out = new ArrayList<>();
        int from = 0;
        while (from < run.size() - 1) {
            SegmentKind kind = kindOf(run.get(from + 1));
            int to = from + 1;
            while (to + 1 < run.size() && kindOf(run.get(to + 1)) == kind) to++;
            for (Reconstructor.Piece piece : reconstructor.reconstruct(COUNTRY, run.subList(from, to + 1), options)) {
                out.add(new RouteSegment(kind, piece.coords(), piece.fallback()));
            }
            from = to;
        }
        return out;
    }

    private static SegmentKind kindOf(Waypoint arriving) {
        return arriving.isVehicle() ? SegmentKind.VEHICLE : SegmentKind.WALK;
    }

    private RouteSegment estimated(GeoPoint from, GeoPoint to) {
        List<GeoPoint> route = osrmClient.route(COUNTRY, from, to);
        return route.isEmpty()
                ? new RouteSegment(SegmentKind.ESTIMATED, List.of(from, to), true)
                : new RouteSegment(SegmentKind.ESTIMATED, route, false);
    }

    private static GeoPoint lastCoord(List<RouteSegment> segments) {
        List<GeoPoint> coords = segments.get(segments.size() - 1).coords();
        return coords.get(coords.size() - 1);
    }
}
