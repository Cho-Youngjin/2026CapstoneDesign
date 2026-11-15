package com.travelfootsteps.route;

import java.util.List;

// 복원한 경로의 구간 하나. fallback=true면 OSRM이 꺼져 있거나 매칭에 실패해 직선으로 대신 채운 구간이다
// (앱은 "도로 맞춤을 못 했어요"라고 안내한다, 설계 9-4).
public record RouteSegment(SegmentKind kind, List<GeoPoint> coords, boolean fallback) {
}
