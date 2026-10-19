package com.travelfootsteps.chat;

/**
 * 누가 어디까지 읽었는지 (Plan D Task 7). {@code /topic/rooms/{roomId}/read}로 퍼뜨리는 바디이자, 서비스가 커밋 뒤
 * 전송을 맡기려고 내는 스프링 이벤트이기도 하다({@link ChatMessageBroadcaster}).
 */
public record ReadEvent(Long roomId, String uid, Long lastReadMessageId) {
}
