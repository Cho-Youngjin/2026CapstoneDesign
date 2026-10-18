package com.travelfootsteps.chat;

import java.time.OffsetDateTime;

/**
 * 메시지 하나. REST 응답(보내기·조회)과 STOMP 브로드캐스트(/topic/rooms/{id}/messages)가
 * <b>같은 모양</b>을 쓴다 — 앱은 두 경로로 온 메시지를 같은 모델로 파싱하고 id로 중복을 걸러낸다.
 *
 * <p>{@code imageUrl}은 사진 메시지(Plan D Task 6)의 내려받기 주소({@code /api/rooms/{roomId}/images/{id}}, 서버 기준
 * 상대 경로)다. 글자 메시지는 null. 서버 디스크 경로는 내보내지 않는다 — 앱은 이 주소로 받고, 서버가 멤버인지 확인한다.
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
        String imageUrl = message.getType() == MessageType.IMAGE
                ? "/api/rooms/" + message.getRoomId() + "/images/" + message.getId()
                : null;
        return new MessageResponse(message.getId(), message.getRoomId(), message.getSenderUid(),
                message.getType(), message.getText(), imageUrl, message.getCreatedAt());
    }
}
