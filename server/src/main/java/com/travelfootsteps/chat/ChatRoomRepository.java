package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {

    /** 초대 코드는 대문자로 저장되므로, 호출부가 입력을 대문자로 바꿔서 넘겨야 한다. */
    Optional<ChatRoom> findByInviteCode(String inviteCode);

    /**
     * 내가 멤버인 방 목록. Task 1에서는 만든 순서 최신순이고, 메시지가 생기는 Task 2에서
     * "최근 메시지순"으로 바꾼다. created_at이 같은 경우를 대비해 id를 보조 정렬로 둔다.
     */
    @Query("""
            select r from ChatRoom r
            where r.id in (select m.roomId from ChatRoomMember m where m.firebaseUid = :uid)
            order by r.createdAt desc, r.id desc
            """)
    List<ChatRoom> findRoomsOf(@Param("uid") String firebaseUid);
}
