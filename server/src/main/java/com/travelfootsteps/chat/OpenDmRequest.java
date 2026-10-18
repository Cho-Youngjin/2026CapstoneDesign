package com.travelfootsteps.chat;

import jakarta.validation.constraints.NotBlank;

/**
 * {@code POST /api/rooms/dm}의 요청 바디 (Plan D Task 5).
 *
 * <p>요청 바디(JSON)를 Java 객체로 바꾸는 것은 Spring MVC가 컨트롤러를 부르기 직전에 하고, 컨트롤러의
 * {@code @Valid}가 붙어 있으면 {@code @NotBlank} 같은 검증까지 그때 한다. 검증에 걸리면 컨트롤러 코드는
 * 실행되지 않고 400이 나간다.
 *
 * @param peerUid DM을 열 상대의 Firebase uid. 같은 그룹 멤버여야 한다(서비스가 검사)
 */
public record OpenDmRequest(
        @NotBlank String peerUid
) {
    // record의 "compact 생성자" — 필드에 값을 넣기 전에 앞뒤 공백을 잘라 둔다(JoinRoomRequest와 같은 방식).
    public OpenDmRequest {
        peerUid = peerUid == null ? null : peerUid.strip();
    }
}
