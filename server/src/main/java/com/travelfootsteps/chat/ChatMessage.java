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
 * 생성 팩토리는 메시지 저장을 구현하는 Plan D Task 2에서 추가한다.
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

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;
}
