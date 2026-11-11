package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;

/**
 * hmm_steps: 걸음 수로 전이 확률을 정하는 은닉 마르코프 모델 맵 매칭(설계 6-3, 제안).
 *
 * <p>틀은 Newson & Krumm, "Hidden Markov Map Matching Through Noise and Sparseness"(ACM GIS 2009)를 따른다.
 * <ul>
 *   <li>후보: 점마다 OSRM /nearest로 200m(원문 3.1절) 안의 도로 위 점 최대 5개.</li>
 *   <li>방사 확률(원문 식 1): 점과 후보 사이 거리의 가우시안. σ = max(점 정확도, σ 하한). 같은 점의 후보끼리만
 *       비교되므로 정규화 상수는 빼고 로그 값 -0.5(d/σ)²만 쓴다.</li>
 *   <li>전이 확률(원문 식 2): exp(-|도로 경로거리 - 걸은 거리| / β). 원문은 걸은 거리 자리에 두 점의 직선거리를
 *       쓴다. 제안은 걸음 수 × 보폭을 쓴다 — 점이 드물어 길이 꺾여도 실제로 걸은 거리를 안다. 걸음 정보가 없거나
 *       탈것이면 원문대로 직선거리다. 도로 경로거리는 연속한 두 점의 후보 쌍을 OSRM /table로 한 번에 구한다.</li>
 *   <li>차이가 2000m 이상인 전이는 불가능으로 본다(원문 4.2절, OSRM MAX_DISTANCE_DELTA).</li>
 *   <li>비터비로 가장 그럴듯한 후보 순서를 고르고, 고른 후보 사이를 OSRM /route로 잇는다.</li>
 * </ul>
 * 후보가 없는 점이나 모든 전이가 불가능한 곳에서는 사슬이 끊긴다(원문 4.2절의 break). 원문은 끊긴 곳 양옆 점을
 * 지워 가며 다시 이어 보지만, 여기서는 끊긴 곳만 직선(fallback)으로 잇고 양쪽을 따로 매칭한다.
 */
class HmmStepsReconstructor implements Reconstructor {

    static final int CANDIDATES = 5;
    static final double CANDIDATE_RADIUS_M = 200;
    static final double MAX_DISTANCE_DELTA_M = 2000;
    // OSRM은 양방향 도로의 두 방향을 같은 위치로 두 번 준다. 이보다 가까운 후보는 하나로 본다.
    static final double SAME_CANDIDATE_M = 1.0;

    private final OsrmClient osrmClient;

    HmmStepsReconstructor(OsrmClient osrmClient) {
        this.osrmClient = osrmClient;
    }

    @Override
    public List<Piece> reconstruct(String country, List<Waypoint> run, HmmOptions options) {
        HmmOptions o = HmmOptions.orDefaults(options);
        int n = run.size();
        List<List<GeoPoint>> candidates = new ArrayList<>();
        for (Waypoint w : run) {
            candidates.add(distinct(osrmClient.nearestCandidates(country, w.point(), CANDIDATES, CANDIDATE_RADIUS_M)));
        }

        // chosen[t]: 고른 후보(없으면 null), chain[t]: 사슬 번호(-1이면 후보 없음).
        GeoPoint[] chosen = new GeoPoint[n];
        int[] chain = new int[n];
        int chains = 0;
        int chainStart = -1;
        double[] score = null;
        List<int[]> back = new ArrayList<>();

        for (int t = 0; t < n; t++) {
            List<GeoPoint> cands = candidates.get(t);
            if (cands.isEmpty()) {
                if (chainStart >= 0) backtrack(chainStart, t - 1, score, back, candidates, chosen, chain, chains++);
                chainStart = -1;
                chain[t] = -1;
                continue;
            }
            double[] emission = emissions(run.get(t), cands, o);
            if (chainStart < 0) {
                chainStart = t;
                score = emission;
                back = new ArrayList<>();
                back.add(null);
                continue;
            }

            List<GeoPoint> previous = candidates.get(t - 1);
            List<List<Double>> table = osrmClient.table(country, previous, cands);
            double walked = walkedDistance(run.get(t - 1), run.get(t), o);
            double[] next = new double[cands.size()];
            int[] from = new int[cands.size()];
            boolean reachable = false;
            for (int j = 0; j < cands.size(); j++) {
                double best = Double.NEGATIVE_INFINITY;
                int arg = -1;
                for (int i = 0; i < previous.size() && !table.isEmpty(); i++) {
                    Double route = table.get(i).get(j);
                    if (route == null || score[i] == Double.NEGATIVE_INFINITY) continue;
                    double diff = Math.abs(route - walked);
                    if (diff >= MAX_DISTANCE_DELTA_M) continue;
                    double s = score[i] - diff / o.betaM();
                    if (s > best) {
                        best = s;
                        arg = i;
                    }
                }
                next[j] = arg < 0 ? Double.NEGATIVE_INFINITY : best + emission[j];
                from[j] = arg;
                reachable |= arg >= 0;
            }
            if (!reachable) {
                // 어느 후보로도 건너갈 수 없다(OSRM /table 실패 포함) — 여기서 사슬을 끊고 새로 시작한다.
                backtrack(chainStart, t - 1, score, back, candidates, chosen, chain, chains++);
                chainStart = t;
                score = emission;
                back = new ArrayList<>();
                back.add(null);
                continue;
            }
            score = next;
            back.add(from);
        }
        if (chainStart >= 0) backtrack(chainStart, n - 1, score, back, candidates, chosen, chain, chains);

        return pieces(country, run, chosen, chain);
    }

    /** 걸은 거리: 걸음 수 × 보폭. 걸음을 모르거나 탈것이거나 절제 실험(useSteps=false)이면 두 점의 직선거리. */
    static double walkedDistance(Waypoint previous, Waypoint current, HmmOptions o) {
        if (o.useSteps() && current.stepsSincePrev() != null && !current.isVehicle()) {
            return current.stepsSincePrev() * o.strideM();
        }
        return GeoMath.haversine(previous.point(), current.point());
    }

    private static double[] emissions(Waypoint w, List<GeoPoint> cands, HmmOptions o) {
        double sigma = Math.max(w.accuracy() != null ? w.accuracy() : o.sigmaMinM(), o.sigmaMinM());
        double[] out = new double[cands.size()];
        for (int j = 0; j < cands.size(); j++) {
            double d = GeoMath.haversine(w.point(), cands.get(j)) / sigma;
            out[j] = -0.5 * d * d;
        }
        return out;
    }

    private static List<GeoPoint> distinct(List<GeoPoint> raw) {
        List<GeoPoint> out = new ArrayList<>();
        for (GeoPoint p : raw) {
            if (out.stream().noneMatch(q -> GeoMath.haversine(p, q) < SAME_CANDIDATE_M)) out.add(p);
        }
        return out;
    }

    /** 사슬의 마지막 단계에서 점수가 가장 높은 후보부터 거꾸로 따라가며 고른다. 같은 점수면 가까운 후보가 먼저다. */
    private static void backtrack(int start, int end, double[] lastScore, List<int[]> back,
                                  List<List<GeoPoint>> candidates, GeoPoint[] chosen, int[] chain, int chainNo) {
        int best = 0;
        for (int j = 1; j < lastScore.length; j++) {
            if (lastScore[j] > lastScore[best]) best = j;
        }
        for (int t = end; t >= start; t--) {
            chosen[t] = candidates.get(t).get(best);
            chain[t] = chainNo;
            if (t > start) best = back.get(t - start)[best];
        }
    }

    /** 같은 사슬 안의 이웃은 /route로, 끊긴 곳은 직선(fallback)으로 잇고, fallback이 같은 다리끼리 한 조각으로 묶는다. */
    private List<Piece> pieces(String country, List<Waypoint> run, GeoPoint[] chosen, int[] chain) {
        List<Piece> out = new ArrayList<>();
        List<GeoPoint> coords = new ArrayList<>();
        boolean fallback = false;
        for (int t = 0; t + 1 < run.size(); t++) {
            GeoPoint a = chosen[t] != null ? chosen[t] : run.get(t).point();
            GeoPoint b = chosen[t + 1] != null ? chosen[t + 1] : run.get(t + 1).point();
            List<GeoPoint> leg;
            boolean legFallback;
            if (chain[t] >= 0 && chain[t] == chain[t + 1]) {
                List<GeoPoint> route = GeoMath.haversine(a, b) < SAME_CANDIDATE_M ? List.of(a, b)
                        : osrmClient.route(country, a, b);
                legFallback = route.isEmpty();
                leg = legFallback ? List.of(a, b) : route;
            } else {
                legFallback = true;
                leg = List.of(a, b);
            }
            if (!coords.isEmpty() && legFallback != fallback) {
                out.add(new Piece(coords, fallback));
                coords = new ArrayList<>(List.of(coords.get(coords.size() - 1)));
            }
            fallback = legFallback;
            append(coords, leg);
        }
        out.add(new Piece(coords, fallback));
        return out;
    }

    // 다리의 첫 점이 앞 다리의 끝과 같은 자리면 한 번만 넣는다.
    private static void append(List<GeoPoint> coords, List<GeoPoint> leg) {
        int skip = !coords.isEmpty() && GeoMath.haversine(coords.get(coords.size() - 1), leg.get(0)) < 0.5 ? 1 : 0;
        coords.addAll(leg.subList(skip, leg.size()));
    }
}
