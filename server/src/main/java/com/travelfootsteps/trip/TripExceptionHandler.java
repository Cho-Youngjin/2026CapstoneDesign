package com.travelfootsteps.trip;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

// @RestControllerAdvice(basePackageClasses = TripController.class): 이 어드바이스가 처리하는
// 예외 핸들러를 trip 패키지의 컨트롤러(TripController)에만 적용한다 — 프로젝트 전체 공통
// 예외 핸들러가 아니라 이 패키지 전용이라는 뜻이다. TripController가 TripNotFoundException을
// 던지면(존재하지 않거나 남의 소유인 여행) 스프링이 이 클래스의 handleNotFound()를 찾아 실행해
// 404 응답으로 바꿔준다.
@RestControllerAdvice(basePackageClasses = TripController.class)
public class TripExceptionHandler {

    @ExceptionHandler(TripNotFoundException.class)
    public ResponseEntity<Void> handleNotFound(TripNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
}
