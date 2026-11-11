package com.travelfootsteps.route;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

// 복원 요청의 머문 곳 하나(재생기 stays.csv의 한 행). 이 시간 범위 안의 점은 중심 하나로 바뀐다(설계 6-2의 1).
public record StayInput(
        @NotNull Long arrive,
        @NotNull Long leave,
        @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
        @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng
) {
    // @AssertTrue: Bean Validation이 이 메서드를 "ordered"라는 속성으로 보고 true인지 검사한다.
    // 필드 하나가 아니라 두 필드의 관계(도착 ≤ 출발)를 검사할 때 쓴다.
    @AssertTrue(message = "arrive는 leave보다 늦을 수 없다")
    public boolean isOrdered() {
        return arrive == null || leave == null || arrive <= leave;
    }
}
