package com.travelfootsteps.chat;

/** JPEG·PNG·WEBP가 아닌 파일(앞부분 바이트로 판정). {@link ChatExceptionHandler}가 415로 바꾼다. */
public class UnsupportedChatImageException extends RuntimeException {
}
