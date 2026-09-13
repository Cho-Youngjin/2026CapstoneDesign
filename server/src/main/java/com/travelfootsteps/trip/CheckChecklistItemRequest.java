package com.travelfootsteps.trip;

import jakarta.validation.constraints.NotNull;

// POST /api/trips/{tripId}/checklist/{itemId}/check의 요청 바디. Boolean(래퍼 타입)을 쓰고
// @NotNull을 붙인 이유: 요청에 "checked" 필드 자체가 빠져 있는 실수를 (원시 boolean이었다면
// 조용히 false로 역직렬화될 것을) 400 Bad Request로 명시적으로 걸러내기 위해서다.
public record CheckChecklistItemRequest(@NotNull Boolean checked) {
}
