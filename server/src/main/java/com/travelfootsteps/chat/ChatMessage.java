package com.travelfootsteps.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

/**
 * 채팅 메시지. id는 서버가 매기는 단조 증가값이라 "이 id보다 오래된 메시지" 페이지 조회와
 * 읽음 위치({@link ChatRoomMember#getLastReadMessageId()}) 비교의 기준으로 그대로 쓴다.
 */
@Entity
@Table(name = "chat_message")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ChatMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "room_id", nullable = false)
    private Long roomId;

    @Column(name = "sender_uid", nullable = false, length = 128)
    private String senderUid;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private MessageType type;

    @Column(length = 1000)
    private String text;

    /**
     * 사진 메시지만 값이 있다(Plan D Task 6). {@link ChatImageStorage}의 저장 디렉터리 안 상대 경로 —
     * 서버 안에서만 쓰고 응답에는 내보내지 않는다(응답은 내려받기 주소 {@code imageUrl}을 준다).
     */
    @Column(name = "image_path", length = 300)
    private String imagePath;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /** 텍스트 메시지. 앞뒤 공백 제거와 길이 검증은 요청 DTO에서 끝난 값을 받는다. */
    public static ChatMessage text(Long roomId, String senderUid, String text) {
        ChatMessage message = new ChatMessage();
        message.roomId = roomId;
        message.senderUid = senderUid;
        message.type = MessageType.TEXT;
        message.text = text;
        message.createdAt = OffsetDateTime.now();
        return message;
    }

    /** 사진 메시지. 파일은 이미 저장소에 저장된 뒤이고, [imagePath]는 그 상대 경로다. */
    public static ChatMessage image(Long roomId, String senderUid, String imagePath) {
        ChatMessage message = new ChatMessage();
        message.roomId = roomId;
        message.senderUid = senderUid;
        message.type = MessageType.IMAGE;
        message.imagePath = imagePath;
        message.createdAt = OffsetDateTime.now();
        return message;
    }
}
