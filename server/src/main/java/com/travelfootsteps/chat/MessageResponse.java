package com.travelfootsteps.chat;

import java.time.OffsetDateTime;

/**
 * 메시지 하나. REST 응답(보내기·조회)과 STOMP 브로드캐스트(/topic/rooms/{id}/messages)가
 * <b>같은 모양</b>을 쓴다 — 앱은 두 경로로 온 메시지를 같은 모델로 파싱하고 id로 중복을 걸러낸다.
 *
 * <p>{@code imageUrl}은 사진 메시지(Plan D Task 6)에서 채워지며, 그 전까지는 항상 null이다.
 */
public record MessageResponse(
        Long id,
        Long roomId,
        String senderUid,
        MessageType type,
        String text,
        String imageUrl,
        OffsetDateTime createdAt
) {
    static MessageResponse of(ChatMessage message) {
        return new MessageResponse(message.getId(), message.getRoomId(), message.getSenderUid(),
                message.getType(), message.getText(), null, message.getCreatedAt());
    }
}
