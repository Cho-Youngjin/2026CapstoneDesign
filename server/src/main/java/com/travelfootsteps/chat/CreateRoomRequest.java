package com.travelfootsteps.chat;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 그룹 방 만들기 요청.
 *
 * <p>앞뒤 공백은 생성자에서 잘라낸다 — Bean Validation은 객체가 만들어진 <b>뒤에</b> 실행되므로,
 * {@code @NotBlank}·{@code @Size}는 자른 값을 기준으로 검사한다. 그래서 공백만 있는 이름은
 * 빈 문자열이 되어 400이고, "앞뒤 공백 + 50자"인 이름은 자른 뒤 50자라 통과한다.
 */
public record CreateRoomRequest(
        @NotBlank @Size(max = 50) String name
) {
    public CreateRoomRequest {
        name = name == null ? null : name.strip();
    }
}
