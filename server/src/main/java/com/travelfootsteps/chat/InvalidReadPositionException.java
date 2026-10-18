package com.travelfootsteps.chat;

/** 읽음 위치로 보낸 메시지 id가 그 방의 메시지가 아니다. {@link ChatExceptionHandler}가 400으로 바꾼다. */
public class InvalidReadPositionException extends RuntimeException {
}
