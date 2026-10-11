package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ChatRoomMemberRepository extends JpaRepository<ChatRoomMember, ChatRoomMember.Key> {

    /**
     * 멤버십 검사. REST(RoomService.requireMember)와 STOMP 구독 인터셉터(Task 2)가 모두 이것을 쓴다.
     * PK (room_id, firebase_uid) 인덱스로 바로 찾는다.
     */
    boolean existsByRoomIdAndFirebaseUid(Long roomId, String firebaseUid);

    /** 방 상세의 멤버 목록 — 참여한 순서라 만든 사람이 항상 맨 앞이다. */
    List<ChatRoomMember> findByRoomIdOrderByJoinedAtAsc(Long roomId);

    long countByRoomId(Long roomId);
}
