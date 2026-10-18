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
 * 채팅방. GROUP과 DM이 같은 테이블을 쓴다 (V11__chat.sql 주석 참고).
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

    /** DM만 값이 있다. 두 사람 uid를 정렬해 이은 값({@link #dmKeyOf}) — 같은 두 사람의 DM을 하나로 묶는 열쇠. */
    @Column(name = "dm_key", length = 260, unique = true)
    private String dmKey;

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

    /** 1:1 DM 방을 만든다(Plan D Task 5). 이름·초대 코드는 없다 — 앱이 상대 이름으로 표시하고, 코드로는 참여할 수 없다. */
    public static ChatRoom createDm(String dmKey) {
        ChatRoom room = new ChatRoom();
        room.type = RoomType.DM;
        room.dmKey = dmKey;
        room.createdAt = OffsetDateTime.now();
        return room;
    }

    /**
     * 두 사람의 DM 열쇠. uid를 정렬해 이으므로 A가 B에게 열든 B가 A에게 열든 같은 값이 된다.
     * 구분자 {@code |}는 Firebase uid에 쓰이지 않는 문자라 서로 다른 두 쌍이 같은 열쇠가 되지 않는다.
     */
    static String dmKeyOf(String uidA, String uidB) {
        return uidA.compareTo(uidB) <= 0 ? uidA + "|" + uidB : uidB + "|" + uidA;
    }

    /** 미리보기 최대 길이 — chat_room.last_message_preview 컬럼 크기와 같다. */
    static final int PREVIEW_MAX_LENGTH = 100;

    /**
     * 방 목록에 보여 줄 마지막 메시지 미리보기. 저장은 {@link ChatRoomRepository#recordLastMessage}가
     * 조건부 UPDATE로 한다 — 엔티티 필드를 바꾸지 않는 이유는 그 메서드 주석 참고.
     */
    static String previewOf(ChatMessage message) {
        if (message.getType() == MessageType.IMAGE) {
            return "사진";
        }
        String text = message.getText();
        if (text.length() <= PREVIEW_MAX_LENGTH) {
            return text;
        }
        // Java 문자열 길이는 UTF-16 칸 수라, 이모지 같은 문자는 두 칸(서로게이트 쌍)을 쓴다. 자르는 자리가
        // 쌍의 한가운데면 반쪽짜리 문자가 남아 DB에 '?'로 깨져 저장되므로 그 문자 앞에서 자른다.
        int end = PREVIEW_MAX_LENGTH;
        if (Character.isHighSurrogate(text.charAt(end - 1))) {
            end--;
        }
        return text.substring(0, end);
    }
}
