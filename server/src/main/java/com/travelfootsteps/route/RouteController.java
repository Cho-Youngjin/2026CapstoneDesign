package com.travelfootsteps.route;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

// 발걸음 실시간 경로의 도로 스냅과 해외 매핑(국내 이동을 해외 도로 위 걸음으로 옮기기).
// 설계/구현 배경: docs/superpowers/specs/2026-09-30-korea-overseas-mapping-report.md
// 이 경로의 요청/응답 JSON은 앱(app/lib/features/footsteps/data/)과의 계약이다.
@RestController
@RequestMapping("/api/route")
@RequiredArgsConstructor
public class RouteController {

    // 사용자가 고른 해외 출발점이 이 거리(m) 안에 도로가 없으면 재선택을 요구한다.
    private static final double ANCHOR_MAX_DISTANCE_M = 50;
    // 도로 스냅에 쓰는 국가. 실시간 경로는 국내 이동이다.
    private static final String SNAP_COUNTRY = "KR";

    private final OsrmClient osrmClient;
    private final OverseasWalkService overseasWalkService;

    // 스냅에 실패하면(OSRM 꺼짐, 좌표가 너무 멀리 떨어져 있음 등) 받은 좌표를 그대로 돌려준다 —
    // 앱의 snapToRoads()가 별도 실패 분기 없이 항상 쓸 수 있는 좌표를 받는다는 가정에 맞춘 것이다.
    @PostMapping("/snap")
    public List<GeoPoint> snap(@RequestBody @NotNull @Size(max = 500) List<@Valid GeoPoint> points) {
        List<GeoPoint> snapped = osrmClient.match(SNAP_COUNTRY, points);
        return snapped.isEmpty() ? points : snapped;
    }

    @PostMapping("/overseas-anchor/validate")
    public AnchorValidateResponse validateAnchor(@RequestBody @Valid AnchorValidateRequest request) {
        return osrmClient.nearest(request.country(), new GeoPoint(request.lat(), request.lng()), ANCHOR_MAX_DISTANCE_M)
                .map(snapped -> new AnchorValidateResponse(true, snapped))
                .orElseGet(() -> new AnchorValidateResponse(false, null));
    }

    @PostMapping("/overseas-walk")
    public OverseasWalkResponse overseasWalk(@RequestBody @Valid OverseasWalkRequest request) {
        return overseasWalkService.walk(request.country(), request.anchor(), request.points(), request.state());
    }
}
