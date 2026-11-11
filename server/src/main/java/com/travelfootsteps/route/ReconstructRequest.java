package com.travelfootsteps.route;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

// POST /api/route/reconstruct 요청(설계 2026-11-07 6-1). 앱(R7 날짜별 보기)과 R6 분석이 쓰는 계약이다.
// 점은 하루치 드문 점 기준 2000개까지 받는다 — 점마다 OSRM을 여러 번 부르므로 한 요청의 계산량을 묶어 둔다.
// List<@Valid TrackPoint>처럼 타입 인자에 붙인 @Valid는 목록의 원소마다 규칙을 검사하라는 뜻이다.
//  - method : 빠지면 앱 기본값 osrm_match_radius
//  - stays  : 빠지면 머문 곳 없음
//  - hmm    : hmm_steps 조정값. 빠지면 기본값
public record ReconstructRequest(
        ReconstructMethod method,
        @NotNull @Size(max = 2000) List<@NotNull @Valid TrackPoint> points,
        @Size(max = 500) List<@NotNull @Valid StayInput> stays,
        @Valid HmmOptions hmm
) {
}
