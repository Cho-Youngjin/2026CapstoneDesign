package com.travelfootsteps.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.time.OffsetDateTime;

/**
 * 채팅방 멤버. 복합 키 (room_id, firebase_uid)라 같은 사람이 같은 방에 두 번 들어갈 수 없다 —
 * "이미 멤버면 다시 참여해도 중복되지 않는다"는 규칙을 DB가 최종 보장한다.
 *
 * <p>읽음 상태({@link #lastReadMessageId})를 메시지가 아니라 멤버 행에 두는 이유는
 * V10__chat.sql의 chat_room_member 주석 참고.
 */
@Entity
@Table(name = "chat_room_member")
@IdClass(ChatRoomMember.Key.class)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ChatRoomMember {

    @Id
    @Column(name = "room_id")
    private Long roomId;

    @Id
    @Column(name = "firebase_uid", length = 128)
    private String firebaseUid;

    @Column(name = "joined_at", nullable = false)
    private OffsetDateTime joinedAt;

    /** 마지막으로 읽은 메시지 id. null이면 아직 아무것도 읽지 않음 (Plan D Task 7). */
    @Column(name = "last_read_message_id")
    private Long lastReadMessageId;

    public static ChatRoomMember join(Long roomId, String firebaseUid) {
        ChatRoomMember member = new ChatRoomMember();
        member.roomId = roomId;
        member.firebaseUid = firebaseUid;
        member.joinedAt = OffsetDateTime.now();
        return member;
    }

    /**
     * {@link IdClass}용 복합 키. JPA 규약상 기본 생성자·equals·hashCode·Serializable이 필요하고,
     * 필드 이름이 엔티티의 @Id 필드 이름과 같아야 한다.
     *
     * <p>record로 쓰지 않는 이유: Hibernate는 IdClass를 기본 생성자로 만든 뒤 필드에 값을 채우는데,
     * record의 필드는 final이라 리플렉션으로 값을 넣을 수 없다.
     */
    @Getter
    @NoArgsConstructor
    @AllArgsConstructor
    @EqualsAndHashCode
    public static class Key implements Serializable {
        private Long roomId;
        private String firebaseUid;
    }
}
