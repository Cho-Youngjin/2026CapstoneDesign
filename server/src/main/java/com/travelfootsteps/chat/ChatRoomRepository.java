package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
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

    /**
     * 방의 "최근 메시지" 비정규화 값을 갱신한다. 단, 지금 저장된 것보다 <b>새로운(id가 큰) 메시지일 때만</b>.
     *
     * <p>왜 엔티티 필드를 바꾸지 않고 UPDATE 쿼리를 직접 쓰는가: 같은 방에 두 메시지가 거의 동시에 오면
     * 두 트랜잭션이 각자 ChatRoom을 읽어 각자 덮어쓴다. 나중 메시지(N+1)의 트랜잭션이 먼저 커밋되고
     * 앞 메시지(N)가 늦게 커밋되면, 방 목록 미리보기·정렬이 더 오래된 N으로 되돌아간다.
     * 조건을 WHERE에 넣으면 PostgreSQL이 같은 행의 UPDATE를 차례로 처리하면서(행 잠금) 뒤에 오는
     * UPDATE의 조건을 앞선 커밋 결과로 다시 확인하므로, 커밋 순서와 상관없이 가장 새 메시지가 남는다.
     *
     * <p>{@code @Modifying}: 이 {@code @Query}가 SELECT가 아니라 데이터를 바꾸는 쿼리라고 Spring Data에
     * 알린다(없으면 실행 시 오류). {@code clearAutomatically}는 실행 후 영속성 컨텍스트(트랜잭션 안의
     * 엔티티 캐시)를 비워, 같은 트랜잭션에서 방을 다시 읽을 때 DB의 새 값을 보게 한다.
     *
     * @return 실제로 바뀐 행 수. 0이면 이미 더 새로운 메시지가 기록돼 있다는 뜻이다(정상).
     */
    @Modifying(clearAutomatically = true)
    @Query("""
            update ChatRoom r
            set r.lastMessageId = :messageId, r.lastMessagePreview = :preview, r.lastMessageAt = :sentAt
            where r.id = :roomId and (r.lastMessageId is null or r.lastMessageId < :messageId)
            """)
    int recordLastMessage(@Param("roomId") Long roomId, @Param("messageId") Long messageId,
                          @Param("preview") String preview, @Param("sentAt") OffsetDateTime sentAt);
}
