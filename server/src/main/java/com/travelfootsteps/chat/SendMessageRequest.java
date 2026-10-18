package com.travelfootsteps.chat;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 텍스트 메시지 보내기 요청. 앞뒤 공백은 생성자에서 잘라내므로 공백만 있는 메시지는 400이다
 * (CreateRoomRequest와 같은 방식). 1000자 제한은 chat_message.text 컬럼 크기와 같다.
 */
public record SendMessageRequest(
        @NotBlank @Size(max = 1000) String text
) {
    public SendMessageRequest {
        text = text == null ? null : text.strip();
    }
}
