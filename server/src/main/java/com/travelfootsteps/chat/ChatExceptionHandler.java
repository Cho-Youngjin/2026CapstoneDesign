package com.travelfootsteps.chat;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** chat 패키지의 컨트롤러에만 적용된다(TripExceptionHandler와 같은 방식). */
@RestControllerAdvice(basePackageClasses = RoomController.class)
public class ChatExceptionHandler {

    @ExceptionHandler(RoomNotFoundException.class)
    public ResponseEntity<Void> handleNotFound(RoomNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }

    /** 자기 자신에게 DM을 열려는 요청, 빈 사진 파일은 잘못된 요청(400)이다. */
    @ExceptionHandler({SelfDmException.class, InvalidChatImageException.class})
    public ResponseEntity<Void> handleBadRequest(RuntimeException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }

    /** 지원하지 않는 사진 형식 — 415 Unsupported Media Type. */
    @ExceptionHandler(UnsupportedChatImageException.class)
    public ResponseEntity<Void> handleUnsupportedImage(UnsupportedChatImageException e) {
        return ResponseEntity.status(HttpStatus.UNSUPPORTED_MEDIA_TYPE).build();
    }

    /**
     * 사진이 너무 크다 — 413 Payload Too Large. multipart 한도를 넘는 요청은 컨트롤러에 닿기 전에 막혀
     * 이 핸들러가 아니라 스프링 기본 처리(역시 413)로 답한다.
     */
    @ExceptionHandler(ChatImageTooLargeException.class)
    public ResponseEntity<Void> handleTooLarge(ChatImageTooLargeException e) {
        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).build();
    }
}
