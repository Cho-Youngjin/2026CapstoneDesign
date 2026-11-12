package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

/**
 * 격자 도로망을 흉내 내는 가짜 OSRM. 가로 길 y = 0·100·200m(x 0~300), 세로 길 x = 0·100·200·300m(y 0~200).
 * 좌표는 (37.5, 127.0)을 원점으로 한 동쪽 x·북쪽 y 미터다. failing이면 모든 호출이 실패(빈 결과)다.
 * 진짜 OSRM처럼 교차로에서는 두 길의 같은 위치를 후보로 두 번 준다.
 */
class GridOsrm implements OsrmClient {

    static final double LAT0 = 37.5;
    static final double LNG0 = 127.0;
    static final double M_PER_DEG = 6371000.0 * Math.PI / 180;
    static final double[] ROWS = {0, 100, 200};
    static final double[] COLS = {0, 100, 200, 300};

    final boolean failing;
    List<Double> lastRadiuses;
    List<Long> lastTimestamps;
    int matchCalls;

    GridOsrm() {
        this(false);
    }

    GridOsrm(boolean failing) {
        this.failing = failing;
    }

    static GeoPoint at(double x, double y) {
        return new GeoPoint(LAT0 + y / M_PER_DEG, LNG0 + x / (M_PER_DEG * Math.cos(Math.toRadians(LAT0))));
    }

    static double x(GeoPoint p) {
        return (p.lng() - LNG0) * M_PER_DEG * Math.cos(Math.toRadians(LAT0));
    }

    static double y(GeoPoint p) {
        return (p.lat() - LAT0) * M_PER_DEG;
    }

    @Override
    public Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters) {
        return nearestCandidates(country, point, 1, maxDistanceMeters).stream().findFirst();
    }

    @Override
    public List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters) {
        if (failing) return List.of();
        double px = x(point);
        double py = y(point);
        List<double[]> found = new ArrayList<>();   // {x, y, 거리}
        for (double row : ROWS) {
            double sx = Math.max(0, Math.min(300, px));
            found.add(new double[] {sx, row, Math.hypot(px - sx, py - row)});
        }
        for (double col : COLS) {
            double sy = Math.max(0, Math.min(200, py));
            found.add(new double[] {col, sy, Math.hypot(px - col, py - sy)});
        }
        return found.stream()
                .sorted(Comparator.comparingDouble(f -> f[2]))
                .filter(f -> f[2] <= maxDistanceMeters)
                .limit(number)
                .map(f -> at(f[0], f[1]))
                .toList();
    }

    @Override
    public List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations) {
        if (failing) return List.of();
        List<List<Double>> out = new ArrayList<>();
        for (GeoPoint s : sources) {
            List<Double> row = new ArrayList<>();
            for (GeoPoint d : destinations) row.add(shortest(s, d).length);
            out.add(row);
        }
        return out;
    }

    @Override
    public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
        if (failing) return List.of();
        Path path = shortest(from, to);
        List<GeoPoint> out = new ArrayList<>();
        for (double[] c : path.corners) {
            GeoPoint p = at(c[0], c[1]);
            if (out.isEmpty() || GeoMath.haversine(out.get(out.size() - 1), p) > 0.01) out.add(p);
        }
        return out;
    }

    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points) {
        return match(country, points, null, null);
    }

    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps) {
        matchCalls++;
        lastRadiuses = radiuses;
        lastTimestamps = timestamps;
        return failing ? List.of() : points;
    }

    private record Path(Double length, List<double[]> corners) {
    }

    // 두 점이 놓인 길(가로·세로)의 모든 조합 중 가장 짧은 길. 격자라 갈아탈 교차로만 고르면 된다.
    private static Path shortest(GeoPoint from, GeoPoint to) {
        double ax = x(from), ay = y(from), bx = x(to), by = y(to);
        Path best = new Path(null, List.of());
        for (boolean aRow : new boolean[] {true, false}) {
            for (boolean bRow : new boolean[] {true, false}) {
                if (!onStreet(ax, ay, aRow) || !onStreet(bx, by, bRow)) continue;
                List<Path> options = new ArrayList<>();
                if (aRow && bRow) {
                    if (Math.abs(ay - by) < 0.01) options.add(path(ax, ay, bx, by));
                    for (double col : COLS) {
                        options.add(path(ax, ay, col, ay, col, by, bx, by));
                    }
                } else if (!aRow && !bRow) {
                    if (Math.abs(ax - bx) < 0.01) options.add(path(ax, ay, bx, by));
                    for (double row : ROWS) {
                        options.add(path(ax, ay, ax, row, bx, row, bx, by));
                    }
                } else if (aRow) {
                    options.add(path(ax, ay, bx, ay, bx, by));
                } else {
                    options.add(path(ax, ay, ax, by, bx, by));
                }
                for (Path p : options) {
                    if (best.length == null || p.length < best.length - 1e-9) best = p;
                }
            }
        }
        return best;
    }

    private static boolean onStreet(double px, double py, boolean row) {
        if (row) {
            for (double r : ROWS) if (Math.abs(py - r) < 0.01 && px > -0.01 && px < 300.01) return true;
        } else {
            for (double c : COLS) if (Math.abs(px - c) < 0.01 && py > -0.01 && py < 200.01) return true;
        }
        return false;
    }

    private static Path path(double... xy) {
        List<double[]> corners = new ArrayList<>();
        double length = 0;
        for (int i = 0; i < xy.length; i += 2) {
            if (i > 0) length += Math.abs(xy[i] - xy[i - 2]) + Math.abs(xy[i + 1] - xy[i - 1]);
            corners.add(new double[] {xy[i], xy[i + 1]});
        }
        return new Path(length, corners);
    }
}
