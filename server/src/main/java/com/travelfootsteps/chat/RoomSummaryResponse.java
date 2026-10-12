package com.travelfootsteps.chat;

import java.time.OffsetDateTime;

/**
 * 방 목록의 한 줄 (GET /api/rooms). 응답 모양은 Plan D "API 계약"을 처음부터 다 갖추고,
 * 아직 기능이 없는 값은 비워 둔다 — 앱이 Task마다 응답 구조를 바꾸지 않아도 되게 하려는 것이다.
 * <ul>
 *     <li>{@code lastMessagePreview}, {@code lastMessageAt}: 메시지가 생기는 Task 2부터 채워진다</li>
 *     <li>{@code unreadCount}: 읽음 표시 Task 7 전까지 항상 0</li>
 *     <li>{@code dmPeer}: DM Task 5 전까지 항상 null</li>
 * </ul>
 */
public record RoomSummaryResponse(
        Long id,
        RoomType type,
        String name,
        String inviteCode,
        long memberCount,
        String lastMessagePreview,
        OffsetDateTime lastMessageAt,
        long unreadCount,
        MemberResponse dmPeer
) {
    static RoomSummaryResponse of(ChatRoom room, long memberCount) {
        return new RoomSummaryResponse(room.getId(), room.getType(), room.getName(), room.getInviteCode(),
                memberCount, room.getLastMessagePreview(), room.getLastMessageAt(), 0, null);
    }
}
