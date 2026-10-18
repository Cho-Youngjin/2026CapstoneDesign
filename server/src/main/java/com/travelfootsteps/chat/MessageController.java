package com.travelfootsteps.chat;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 채팅 메시지 API (Plan D Task 2). <b>보내기는 여기(REST), 받기는 STOMP 구독</b>으로 나눈다 —
 * REST로 보내면 저장 성공 여부와 메시지 id를 응답으로 확실히 받을 수 있고, STOMP SEND는
 * 성공·실패를 알려주지 않는다. 저장된 메시지는 {@link ChatMessageBroadcaster}가 구독자에게 전한다.
 */
@RestController
@RequestMapping("/api/rooms/{roomId}/messages")
@RequiredArgsConstructor
public class MessageController {

    private final MessageService messageService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public MessageResponse send(@PathVariable Long roomId,
                                @Valid @RequestBody SendMessageRequest request,
                                Authentication authentication) {
        return messageService.sendText(roomId, authentication.getName(), request.text());
    }

    @GetMapping
    public List<MessageResponse> list(@PathVariable Long roomId,
                                      @RequestParam(required = false) Long before,
                                      @RequestParam(defaultValue = "" + MessageService.DEFAULT_PAGE_SIZE) int size,
                                      Authentication authentication) {
        return messageService.messages(roomId, authentication.getName(), before, size);
    }
}
