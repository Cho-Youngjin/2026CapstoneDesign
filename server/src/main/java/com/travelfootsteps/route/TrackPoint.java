package com.travelfootsteps.route;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;

// 복원 요청의 측위 점 하나(재생기 fixes.csv의 한 행, 앱 RoutePoints의 한 행과 같은 내용).
// 이 레코드의 애너테이션은 Bean Validation 규칙이다. 컨트롤러 파라미터에 @Valid가 붙어 있으면 스프링이
// 요청 JSON을 이 객체로 바꾼 직후 규칙을 검사하고, 어기면 컨트롤러 메서드를 부르지 않고 400을 돌려준다.
// 필수 값은 박싱 타입(Long, Double)에 @NotNull을 붙인다 — 기본형(long)은 값이 빠지면 0으로 조용히 채워진다.
//  - t              : 측위 시각(UTC epoch 밀리초)
//  - accuracy       : 정확도(m). 모르면 null(5m로 본다)
//  - stepsSincePrev : 직전 점 이후 걸음 수. 모르면 null
//  - state          : 측위 때 정책 상태. step_budget은 시작 직후 unknown을 쓴다
public record TrackPoint(
        @NotNull Long t,
        @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
        @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng,
        @PositiveOrZero Double accuracy,
        @PositiveOrZero Integer stepsSincePrev,
        @Pattern(regexp = "still|walking|otherMotion|vehicle|unknown") String state
) {
}
