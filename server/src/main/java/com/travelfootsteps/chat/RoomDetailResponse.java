package com.travelfootsteps.chat;

import java.util.List;

/** 방 상세 — 방 만들기·참여 응답과 GET /api/rooms/{id} 응답. 멤버는 참여한 순서다. */
public record RoomDetailResponse(
        Long id,
        RoomType type,
        String name,
        String inviteCode,
        List<MemberResponse> members
) {
    static RoomDetailResponse of(ChatRoom room, List<MemberResponse> members) {
        return new RoomDetailResponse(room.getId(), room.getType(), room.getName(), room.getInviteCode(), members);
    }
}
