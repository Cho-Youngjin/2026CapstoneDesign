package com.travelfootsteps.location;

// StompAuthChannelInterceptor가 CONNECT 프레임 인증에 실패했을 때 던지는 예외.
// ChannelInterceptor#preSend에서 던져진 런타임 예외는 Spring 메시징 인프라가 잡아서
// 클라이언트에게 ERROR 프레임으로 내려보내고 연결을 끊는다 — HTTP 컨트롤러처럼 별도
// @ExceptionHandler를 만들 필요 없이, 이 예외를 던지는 것 자체가 "연결 거부"의 의미다.
public class StompAuthenticationException extends RuntimeException {
    public StompAuthenticationException(String message) {
        super(message);
    }
}
