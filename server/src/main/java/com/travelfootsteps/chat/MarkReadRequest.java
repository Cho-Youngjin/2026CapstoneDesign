package com.travelfootsteps.chat;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * {@code POST /api/rooms/{roomId}/read}의 요청 바디 (Plan D Task 7).
 *
 * <p>{@code @NotNull}·{@code @Positive}는 컨트롤러의 {@code @Valid}가 검사한다 — 비었거나 0 이하면 컨트롤러 코드가
 * 돌기 전에 400이 나간다. 메시지 id는 1부터 매겨지므로 0 이하는 있을 수 없는 값이다.
 *
 * @param lastReadMessageId 화면에 보인 가장 최근 메시지의 id
 */
public record MarkReadRequest(
        @NotNull @Positive Long lastReadMessageId
) {
}
