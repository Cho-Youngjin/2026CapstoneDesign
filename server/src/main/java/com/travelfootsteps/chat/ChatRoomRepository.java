package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {

    /** 초대 코드는 대문자로 저장되므로, 호출부가 입력을 대문자로 바꿔서 넘겨야 한다. */
    Optional<ChatRoom> findByInviteCode(String inviteCode);

    /** 새 초대 코드가 이미 쓰이고 있는지 — RoomService가 저장 전에 확인한다. */
    boolean existsByInviteCode(String inviteCode);

    /**
     * 내가 멤버인 방 목록, 최근 활동순. "최근 활동"은 마지막 메시지 시각이고, 메시지가 아직
     * 없는 방은 만든 시각으로 대신한다 — 그래서 방금 만든 빈 방도 목록 맨 위에 보인다.
     * 시각이 같은 경우를 대비해 id를 보조 정렬로 둔다.
     */
    @Query("""
            select r from ChatRoom r
            where r.id in (select m.roomId from ChatRoomMember m where m.firebaseUid = :uid)
            order by coalesce(r.lastMessageAt, r.createdAt) desc, r.id desc
            """)
    List<ChatRoom> findRoomsOf(@Param("uid") String firebaseUid);
}
