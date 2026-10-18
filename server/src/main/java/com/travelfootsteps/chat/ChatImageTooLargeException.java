package com.travelfootsteps.chat;

/** 사진이 {@link MessageService#MAX_IMAGE_BYTES}를 넘는다. {@link ChatExceptionHandler}가 413으로 바꾼다. */
public class ChatImageTooLargeException extends RuntimeException {
}
