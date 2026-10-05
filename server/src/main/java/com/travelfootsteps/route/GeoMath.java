package com.travelfootsteps.route;

import java.util.ArrayList;
import java.util.List;

// 지리 계산 도움 함수. mock_server.py의 _haversine_distance, _bearing, _destination 등을 옮긴 것이다.
// 방위(bearing)는 라디안(0~2π, 북쪽 기준 시계 방향), 각도 인자는 도(degree)로 쓴다 — 원본과 같다.
final class GeoMath {

    private static final double EARTH_RADIUS_M = 6371000.0;

    private GeoMath() {
    }

    static double haversine(GeoPoint p1, GeoPoint p2) {
        double lat1 = Math.toRadians(p1.lat());
        double lat2 = Math.toRadians(p2.lat());
        double dLat = lat2 - lat1;
        double dLon = Math.toRadians(p2.lng()) - Math.toRadians(p1.lng());
        double a = Math.pow(Math.sin(dLat / 2), 2)
                + Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(dLon / 2), 2);
        return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a));
    }

    static double bearing(GeoPoint p1, GeoPoint p2) {
        double lat1 = Math.toRadians(p1.lat());
        double lat2 = Math.toRadians(p2.lat());
        double dLon = Math.toRadians(p2.lng()) - Math.toRadians(p1.lng());
        double x = Math.sin(dLon) * Math.cos(lat2);
        double y = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
        return mod(Math.atan2(x, y), 2 * Math.PI);
    }

    static double bearingDeg(GeoPoint p1, GeoPoint p2) {
        return Math.toDegrees(bearing(p1, p2));
    }

    /** origin에서 bearingRad 방향으로 distanceMeters만큼 이동한 좌표(구면 삼각법). */
    static GeoPoint destination(GeoPoint origin, double bearingRad, double distanceMeters) {
        double lat1 = Math.toRadians(origin.lat());
        double lon1 = Math.toRadians(origin.lng());
        double angDist = distanceMeters / EARTH_RADIUS_M;
        double lat2 = Math.asin(Math.sin(lat1) * Math.cos(angDist)
                + Math.cos(lat1) * Math.sin(angDist) * Math.cos(bearingRad));
        double lon2 = lon1 + Math.atan2(
                Math.sin(bearingRad) * Math.sin(angDist) * Math.cos(lat1),
                Math.cos(angDist) - Math.sin(lat1) * Math.sin(lat2));
        return new GeoPoint(Math.toDegrees(lat2), Math.toDegrees(lon2));
    }

    /** 각도를 (-180, 180] 범위로 접는다. */
    static double wrap180(double deg) {
        return mod(deg + 180, 360) - 180;
    }

    static double angleDiff(double a, double b) {
        return Math.abs(wrap180(a - b));
    }

    // 파이썬의 %처럼 항상 0 이상으로 나눈 나머지를 돌려준다(Java의 %는 음수가 나온다).
    static double mod(double x, double m) {
        return ((x % m) + m) % m;
    }

    static double polylineLength(List<GeoPoint> pts) {
        double sum = 0;
        for (int i = 1; i < pts.size(); i++) sum += haversine(pts.get(i - 1), pts.get(i));
        return sum;
    }

    static GeoPoint lerp(GeoPoint a, GeoPoint b, double t) {
        return new GeoPoint(a.lat() + (b.lat() - a.lat()) * t, a.lng() + (b.lng() - a.lng()) * t);
    }

    /** pts를 앞에서부터 d미터까지만 자른다. 자른 끝점은 마지막 선분 위를 보간한 점이다. */
    static Truncated truncate(List<GeoPoint> pts, double d) {
        List<GeoPoint> out = new ArrayList<>();
        out.add(pts.get(0));
        double walked = 0;
        for (int i = 1; i < pts.size(); i++) {
            GeoPoint a = pts.get(i - 1);
            GeoPoint b = pts.get(i);
            double seg = haversine(a, b);
            if (seg == 0) continue;
            if (walked + seg >= d) {
                out.add(lerp(a, b, (d - walked) / seg));
                return new Truncated(out, d);
            }
            walked += seg;
            out.add(b);
        }
        return new Truncated(out, walked);
    }

    record Truncated(List<GeoPoint> path, double advance) {
    }

    /** pts를 step미터 간격으로 다시 찍는다. 첫 점은 그대로 둔다. */
    static List<GeoPoint> resample(List<GeoPoint> pts, double step) {
        List<GeoPoint> out = new ArrayList<>();
        if (pts.isEmpty()) return out;
        out.add(pts.get(0));
        double carry = 0;
        for (int i = 1; i < pts.size(); i++) {
            GeoPoint a = pts.get(i - 1);
            GeoPoint b = pts.get(i);
            double seg = haversine(a, b);
            if (seg == 0) continue;
            double pos = step - carry;
            while (pos <= seg) {
                out.add(lerp(a, b, pos / seg));
                pos += step;
            }
            carry = seg - (pos - step);
        }
        return out;
    }
}
