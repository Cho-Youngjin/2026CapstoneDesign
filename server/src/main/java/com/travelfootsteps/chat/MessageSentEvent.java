package com.travelfootsteps.chat;

/**
 * 메시지가 저장됐다는 사실. {@link MessageService}가 트랜잭션 안에서 발행하고,
 * {@link ChatMessageBroadcaster}가 <b>커밋이 끝난 뒤에</b> 받아서 STOMP로 내보낸다.
 */
record MessageSentEvent(MessageResponse message) {
}
