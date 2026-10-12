package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;

/** 페이지 조회(before 커서)와 안 읽은 개수 쿼리는 Plan D Task 2·7에서 추가한다. */
public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {
}
