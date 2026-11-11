package com.travelfootsteps.route;

import java.util.List;

// POST /api/route/reconstruct 응답. method는 실제로 쓴 방법이다(요청에서 빠졌으면 기본값).
public record ReconstructResponse(ReconstructMethod method, List<RouteSegment> segments) {
}
