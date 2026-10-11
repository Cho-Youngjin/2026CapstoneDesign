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
 * 채팅방. GROUP과 DM이 같은 테이블을 쓴다 (V10__chat.sql 주석 참고).
 *
 * <p>멤버는 이 엔티티의 컬렉션으로 들고 있지 않고 {@link ChatRoomMember}를 따로 조회한다 —
 * 프로젝트의 다른 엔티티(Trip ↔ TripTask)처럼 JPA 연관관계 없이 id로만 잇는 방식을 따른다.
 */
@Entity
@Table(name = "chat_room")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ChatRoom {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private RoomType type;

    /** GROUP만 값이 있다. */
    @Column(length = 50)
    private String name;

    /** GROUP만 값이 있다. 대문자 6자리 ({@link InviteCodeGenerator}). */
    @Column(name = "invite_code", length = 6, unique = true)
    private String inviteCode;

    @Column(name = "last_message_id")
    private Long lastMessageId;

    @Column(name = "last_message_preview", length = 100)
    private String lastMessagePreview;

    @Column(name = "last_message_at")
    private OffsetDateTime lastMessageAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    /**
     * 그룹 방을 만든다. 이름의 앞뒤 공백 제거와 길이 검증은 요청 DTO에서 끝난 값을 받는다고 가정한다.
     */
    public static ChatRoom createGroup(String name, String inviteCode) {
        ChatRoom room = new ChatRoom();
        room.type = RoomType.GROUP;
        room.name = name;
        room.inviteCode = inviteCode;
        room.createdAt = OffsetDateTime.now();
        return room;
    }
}
