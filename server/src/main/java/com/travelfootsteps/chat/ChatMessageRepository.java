package com.travelfootsteps.chat;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

/**
 * 메시지 페이지 조회는 "커서" 방식이다 — 페이지 번호(OFFSET) 대신 "이 id보다 오래된 것"으로 자른다.
 * OFFSET은 그사이 새 메시지가 들어오면 페이지 경계가 밀려 같은 메시지가 두 번 보이거나 빠지고,
 * 뒤 페이지로 갈수록 느려진다. id 커서는 둘 다 없고 (room_id, id DESC) 인덱스를 그대로 탄다.
 * Pageable은 개수 제한(LIMIT) 용도로만 쓴다(항상 0페이지).
 */
public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {

    /** 가장 최근 메시지부터 (채팅방에 처음 들어왔을 때). */
    List<ChatMessage> findByRoomIdOrderByIdDesc(Long roomId, Pageable limit);

    /** {@code beforeId}보다 오래된 메시지부터 (위로 스크롤해서 이전 기록을 볼 때). */
    List<ChatMessage> findByRoomIdAndIdLessThanOrderByIdDesc(Long roomId, Long beforeId, Pageable limit);
}
