package com.travelfootsteps.chat;

/**
 * 자기 자신에게 DM을 열려고 할 때. {@link ChatExceptionHandler}가 400으로 바꾼다.
 *
 * <p>404(같은 그룹이 아님)와 구분하는 이유: 이건 "그런 상대가 없다"가 아니라 요청 자체가 잘못된 경우라,
 * 방이나 사람의 존재 여부를 흘릴 걱정이 없다.
 */
public class SelfDmException extends RuntimeException {
}
