package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.concurrent.TimeUnit;

/**
 * 채팅 사진 올리기·내려받기 API (Plan D Task 6). 규칙(멤버 확인, 형식·크기 검사, 파일과 DB 맞추기)은 전부
 * {@link MessageService}에 있다.
 *
 * <p>사진을 보내는 것도 결국 "메시지 보내기"라 응답은 글자 메시지와 같은 {@link MessageResponse}이고, 같은
 * 실시간 경로(/topic/rooms/{roomId}/messages)로 퍼진다.
 */
@RestController
@RequestMapping("/api/rooms/{roomId}/images")
@RequiredArgsConstructor
public class ChatImageController {

    /** 같은 사진을 다시 그릴 때 앱이 매번 받지 않게 하루 동안 재사용을 허락한다. 사진은 바뀌지 않는다. */
    private static final CacheControl CACHE = CacheControl.maxAge(1, TimeUnit.DAYS).cachePrivate();

    private final MessageService messageService;

    /**
     * {@code @RequestPart("file")}: multipart/form-data 요청에서 이름이 "file"인 부분을 꺼낸다. 없으면 스프링이
     * 컨트롤러를 부르기 전에 400으로 답한다. 크기 한도(application.yml의 spring.servlet.multipart)를 넘는 요청은
     * 그보다 먼저, 요청을 읽는 단계에서 413으로 막힌다.
     */
    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public MessageResponse upload(@PathVariable Long roomId,
                                  @RequestPart("file") MultipartFile file,
                                  Authentication authentication) throws IOException {
        return messageService.sendImage(roomId, authentication.getName(), file.getBytes());
    }

    /**
     * 사진 바이트를 그대로 준다. {@code Cache-Control: private}는 "이 사용자의 기기에만 저장하고 중간의 공용 캐시에는
     * 남기지 말라"는 뜻이다 — 멤버만 볼 수 있는 사진이기 때문이다.
     */
    @GetMapping("/{messageId}")
    public ResponseEntity<byte[]> download(@PathVariable Long roomId,
                                           @PathVariable Long messageId,
                                           Authentication authentication) {
        MessageService.ChatImage image = messageService.loadImage(roomId, authentication.getName(), messageId);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(image.contentType()))
                .cacheControl(CACHE)
                .body(image.bytes());
    }
}
