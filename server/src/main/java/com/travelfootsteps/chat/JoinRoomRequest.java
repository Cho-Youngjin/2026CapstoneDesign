package com.travelfootsteps.chat;

import jakarta.validation.constraints.NotBlank;

/**
 * 초대 코드로 참여 요청. 코드는 대문자로 저장되므로 여기서 대문자로 맞추고 앞뒤 공백을 자른다 —
 * 사람이 손으로 옮겨 적는 값이라 "abc234 "처럼 들어와도 같은 방을 찾아야 한다.
 */
public record JoinRoomRequest(
        @NotBlank String inviteCode
) {
    public JoinRoomRequest {
        inviteCode = inviteCode == null ? null : inviteCode.strip().toUpperCase();
    }
}
