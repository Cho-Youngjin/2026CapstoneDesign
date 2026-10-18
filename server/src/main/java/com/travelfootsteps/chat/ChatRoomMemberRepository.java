package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
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

    /**
     * 여러 방의 멤버 수를 쿼리 한 번으로 센다. 방 목록에서 방마다 countByRoomId를 부르면
     * 방이 N개일 때 쿼리가 N번 나가므로(N+1 문제) 목록 조회는 이것을 쓴다.
     */
    @Query("""
            select m.roomId as roomId, count(m) as memberCount
            from ChatRoomMember m
            where m.roomId in :roomIds
            group by m.roomId
            """)
    List<RoomMemberCount> countByRoomIds(@Param("roomIds") Collection<Long> roomIds);

    /** 위 쿼리의 결과 한 줄. Spring Data가 select 별칭(roomId, memberCount)으로 getter를 채운다. */
    interface RoomMemberCount {
        Long getRoomId();

        long getMemberCount();
    }
}
