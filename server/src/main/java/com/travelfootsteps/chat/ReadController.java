package com.travelfootsteps.chat;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 읽음 표시 API (Plan D Task 7). 앱은 채팅방이 화면에 보이는 동안 가장 최근 메시지 id를 1초에 한 번 정도 보낸다.
 * 규칙(줄지 않음, 그 방의 메시지인지)은 {@link MessageService#markRead}에 있다.
 */
@RestController
@RequestMapping("/api/rooms/{roomId}/read")
@RequiredArgsConstructor
public class ReadController {

    private final MessageService messageService;

    /** 응답 바디가 없어 204(No Content)로 답한다. */
    @PostMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void markRead(@PathVariable Long roomId,
                         @Valid @RequestBody MarkReadRequest request,
                         Authentication authentication) {
        messageService.markRead(roomId, authentication.getName(), request.lastReadMessageId());
    }
}
