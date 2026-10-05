package com.travelfootsteps.route;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

// points는 한국 좌표열이고 첫 점은 직전 요청의 마지막 한국 좌표다(이동량을 재는 기준점).
// 개수 상한은 방어용이다 — 요청 실패가 이어지면 앱이 구간을 늘려 재시도하므로 어느 정도는
// 커질 수 있지만, 무한정 받으면 한 요청의 계산량이 끝없이 늘어난다.
public record OverseasWalkRequest(
        @NotBlank String country,
        @NotNull @Valid GeoPoint anchor,
        @NotNull @Size(max = 500) List<@Valid GeoPoint> points,
        @Valid WalkState state
) {
}
