package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
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

    /**
     * 읽음 위치를 앞으로만 옮긴다(Plan D Task 7). 지금 값보다 클 때만 바꾸므로, 늦게 도착한 옛 요청이 위치를 되돌리지
     * 못한다 — "읽고 → 비교 → 쓰기"를 자바에서 하면 두 요청이 동시에 오면 어긋나지만, 한 UPDATE 문 안의 조건은 DB가
     * 한 번에 처리한다. 바꾼 행 수(0 또는 1)를 돌려준다.
     *
     * <p>{@code @Modifying}: SELECT가 아니라 데이터를 바꾸는 쿼리라는 표시. {@code clearAutomatically}는 실행 뒤
     * 영속성 컨텍스트(JPA가 들고 있는 엔티티 캐시)를 비워, 같은 트랜잭션에서 다시 읽을 때 옛 값이 나오지 않게 한다.
     */
    @Modifying(clearAutomatically = true)
    @Query("""
            update ChatRoomMember m set m.lastReadMessageId = :messageId
            where m.roomId = :roomId and m.firebaseUid = :uid
              and (m.lastReadMessageId is null or m.lastReadMessageId < :messageId)
            """)
    int markRead(@Param("roomId") Long roomId, @Param("uid") String uid, @Param("messageId") Long messageId);

    /**
     * 내 방들의 안 읽은 메시지 수를 <b>쿼리 한 번</b>으로 센다(Plan D 데이터 모델 "안 읽은 개수"). 방마다 따로 세면
     * 방이 N개일 때 쿼리가 N번 나간다(N+1). 안 읽은 메시지가 없는 방은 결과에 없다(0으로 본다).
     * 안 읽은 수 = 내 읽음 위치보다 큰, <b>남이 보낸</b> 메시지 수. (room_id, id DESC) 인덱스를 탄다.
     */
    @Query("""
            select m.roomId as roomId, count(msg) as unreadCount
            from ChatRoomMember m, ChatMessage msg
            where m.firebaseUid = :uid and msg.roomId = m.roomId
              and msg.senderUid <> :uid
              and msg.id > coalesce(m.lastReadMessageId, 0)
            group by m.roomId
            """)
    List<RoomUnreadCount> countUnreadOf(@Param("uid") String uid);

    /** 위 쿼리의 결과 한 줄. */
    interface RoomUnreadCount {
        Long getRoomId();

        long getUnreadCount();
    }
}
