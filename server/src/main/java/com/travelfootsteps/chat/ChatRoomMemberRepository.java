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

    /**
     * 두 사람이 같은 <b>그룹</b> 방에 함께 있는가(Plan D Task 5 — DM은 같은 그룹 멤버끼리만 연다).
     * 멤버 행을 방 id로 두 번 이어 붙여(self join) 한쪽은 A, 다른 쪽은 B인 방이 하나라도 있는지 본다.
     * DM 방은 빼야 한다 — 이미 DM을 튼 사이라는 이유로 새 DM 권한이 생기면 안 되므로.
     */
    @Query("""
            select count(a) > 0
            from ChatRoomMember a, ChatRoomMember b, ChatRoom r
            where a.roomId = b.roomId and r.id = a.roomId
              and r.type = com.travelfootsteps.chat.RoomType.GROUP
              and a.firebaseUid = :uidA and b.firebaseUid = :uidB
            """)
    boolean shareGroup(@Param("uidA") String uidA, @Param("uidB") String uidB);

    /** 여러 방의 멤버를 한 번에 — 방 목록에서 DM 상대를 찾을 때 방마다 조회하지 않으려고 쓴다. */
    List<ChatRoomMember> findByRoomIdIn(Collection<Long> roomIds);
}
