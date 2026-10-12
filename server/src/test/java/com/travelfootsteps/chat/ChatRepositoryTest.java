package com.travelfootsteps.chat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * V11__chat.sql 스키마와 채팅 엔티티·리포지토리가 실제 PostgreSQL에서 맞물리는지 확인한다.
 * Hibernate의 ddl-auto: validate가 컬럼 이름·타입 불일치를 잡아 주고, 여기서는 복합 키,
 * 커스텀 쿼리, DB 제약(UNIQUE·CHECK)이 의도대로 동작하는지를 본다.
 *
 * 초대 코드 UNIQUE 제약은 마지막 방어선이다 — RoomService는 저장 전에 existsByInviteCode로
 * 겹치는 코드를 걸러내고, 확인과 저장 사이에 다른 요청이 끼어드는 드문 경우만 이 제약이 막는다
 * (이유는 RoomService.newInviteCode 주석 참고).
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class ChatRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void flyway(DynamicPropertyRegistry registry) {
        registry.add("spring.flyway.enabled", () -> "true");
    }

    @Autowired ChatRoomRepository roomRepository;
    @Autowired ChatRoomMemberRepository memberRepository;
    @Autowired AppUserRepository userRepository;

    @Test
    void 방과_멤버를_저장하면_멤버십을_확인할_수_있다() {
        ChatRoom room = roomRepository.saveAndFlush(ChatRoom.createGroup("도쿄 여행", "ABC234"));
        memberRepository.saveAndFlush(ChatRoomMember.join(room.getId(), "uid-a"));

        assertThat(room.getId()).isNotNull();
        assertThat(room.getType()).isEqualTo(RoomType.GROUP);
        assertThat(memberRepository.existsByRoomIdAndFirebaseUid(room.getId(), "uid-a")).isTrue();
        assertThat(memberRepository.existsByRoomIdAndFirebaseUid(room.getId(), "uid-b")).isFalse();
    }

    @Test
    void 초대_코드로_방을_찾는다() {
        ChatRoom room = roomRepository.saveAndFlush(ChatRoom.createGroup("오사카", "XYZ789"));

        assertThat(roomRepository.findByInviteCode("XYZ789")).get()
                .extracting(ChatRoom::getId).isEqualTo(room.getId());
        assertThat(roomRepository.findByInviteCode("NOPE22")).isEmpty();
    }

    @Test
    void 같은_초대_코드로_두_번째_방을_만들면_DB가_거부한다() {
        roomRepository.saveAndFlush(ChatRoom.createGroup("첫 번째", "DUP234"));

        assertThatThrownBy(() -> roomRepository.saveAndFlush(ChatRoom.createGroup("두 번째", "DUP234")))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void 초대_코드가_없는_그룹방은_DB가_거부한다() {
        // chat_room_group_fields_check — 서비스 코드에 버그가 있어도 코드 없는 그룹방은 저장되지 않는다
        assertThatThrownBy(() -> roomRepository.saveAndFlush(ChatRoom.createGroup("코드 없음", null)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void 내_방_목록은_내가_속한_방만_최신순으로_돌려준다() {
        ChatRoom first = roomRepository.saveAndFlush(ChatRoom.createGroup("첫 번째", "LST234"));
        ChatRoom second = roomRepository.saveAndFlush(ChatRoom.createGroup("두 번째", "LST345"));
        ChatRoom others = roomRepository.saveAndFlush(ChatRoom.createGroup("남의 방", "LST456"));
        memberRepository.saveAndFlush(ChatRoomMember.join(first.getId(), "uid-list"));
        memberRepository.saveAndFlush(ChatRoomMember.join(second.getId(), "uid-list"));
        memberRepository.saveAndFlush(ChatRoomMember.join(others.getId(), "uid-other"));

        List<ChatRoom> rooms = roomRepository.findRoomsOf("uid-list");

        assertThat(rooms).extracting(ChatRoom::getName).containsExactly("두 번째", "첫 번째");
    }

    @Test
    void 멤버_목록은_참여한_순서다() {
        ChatRoom room = roomRepository.saveAndFlush(ChatRoom.createGroup("순서", "ORD234"));
        memberRepository.saveAndFlush(ChatRoomMember.join(room.getId(), "uid-creator"));
        memberRepository.saveAndFlush(ChatRoomMember.join(room.getId(), "uid-joiner"));

        assertThat(memberRepository.findByRoomIdOrderByJoinedAtAsc(room.getId()))
                .extracting(ChatRoomMember::getFirebaseUid)
                .containsExactly("uid-creator", "uid-joiner");
        assertThat(memberRepository.countByRoomId(room.getId())).isEqualTo(2);
    }

    @Test
    void 여러_사용자의_프로필을_한_번에_가져온다() {
        userRepository.saveAndFlush(AppUser.create("uid-p1", "성주", "https://example.com/1.png"));
        userRepository.saveAndFlush(AppUser.create("uid-p2", "영진", null));

        List<AppUser> users = userRepository.findByFirebaseUidIn(List.of("uid-p1", "uid-p2", "uid-none"));

        assertThat(users).extracting(AppUser::getDisplayName).containsExactlyInAnyOrder("성주", "영진");
    }
}
