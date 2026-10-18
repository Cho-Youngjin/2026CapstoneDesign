package com.travelfootsteps.chat;

/**
 * 방 멤버 한 명. 프로필을 아직 올리지 않은 사용자는 {@code profile}이 null이고, 이때 이름과
 * 사진은 null로 내려간다 — 앱이 "알 수 없음"으로 표시한다.
 */
public record MemberResponse(
        String uid,
        String displayName,
        String photoUrl,
        Long lastReadMessageId
) {
    static MemberResponse of(ChatRoomMember member, AppUser profile) {
        return new MemberResponse(
                member.getFirebaseUid(),
                profile != null ? profile.getDisplayName() : null,
                profile != null ? profile.getPhotoUrl() : null,
                member.getLastReadMessageId());
    }
}
