package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * DM 방을 <b>별도 트랜잭션</b>에서 만든다 (Plan D Task 5).
 *
 * <p><b>왜 따로 떼어 냈나</b> — 두 사람이 동시에 서로에게 DM을 열면, 둘 다 "아직 없다"를 확인한 뒤 저장하려 하고
 * 늦은 쪽은 {@code dm_key} UNIQUE 제약에 걸린다. 그때는 먼저 만든 방을 다시 찾아 돌려주면 된다. 그런데
 * PostgreSQL은 트랜잭션 안에서 제약 위반이 한 번 나면 그 트랜잭션의 이후 쿼리를 모두 거부한다. 그래서 저장을
 * 바깥 트랜잭션과 분리해야, 실패한 뒤에도 바깥에서 다시 조회할 수 있다.
 *
 * <p>{@code @Transactional(propagation = REQUIRES_NEW)}: 부르는 쪽에 트랜잭션이 있어도 그것을 잠시 멈추고
 * <b>새 트랜잭션</b>을 연다. 이 메서드가 실패하면 새 트랜잭션만 롤백되고 바깥 트랜잭션은 멀쩡하다.
 *
 * <p>같은 클래스 안의 메서드를 부르면 Spring의 트랜잭션 처리(프록시)를 거치지 않아 {@code @Transactional}이
 * 무시된다. 그래서 RoomService 안의 private 메서드가 아니라 별도 빈({@code @Component})으로 둔다.
 */
@Component
@RequiredArgsConstructor
class DmRoomCreator {

    private final ChatRoomRepository roomRepository;
    private final ChatRoomMemberRepository memberRepository;

    /**
     * 방과 두 멤버를 저장하고 커밋한다. {@code saveAndFlush}로 INSERT를 바로 보내야 UNIQUE 위반이 이 메서드
     * 안에서(커밋 전에) 드러난다.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public ChatRoom create(String dmKey, String openerUid, String peerUid) {
        ChatRoom room = roomRepository.saveAndFlush(ChatRoom.createDm(dmKey));
        memberRepository.save(ChatRoomMember.join(room.getId(), openerUid));
        memberRepository.save(ChatRoomMember.join(room.getId(), peerUid));
        return room;
    }
}
