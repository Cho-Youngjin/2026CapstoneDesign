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

    /** 자기 자신에게 DM을 열려는 요청은 잘못된 요청(400)이다. */
    @ExceptionHandler(SelfDmException.class)
    public ResponseEntity<Void> handleSelfDm(SelfDmException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }
}
