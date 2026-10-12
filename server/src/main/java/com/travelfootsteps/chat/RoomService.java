package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 채팅방 규칙을 한곳에 모은다 — 방 만들기, 초대 코드 참여, 조회, 그리고 멤버십 검사.
 *
 * <p>멤버십 검사({@link #requireMember}, {@link #isMember})를 여기 두는 이유: REST 컨트롤러와
 * STOMP 구독 인터셉터(Plan D Task 2)가 <b>같은 규칙</b>을 써야 한다. 두 군데서 따로 검사하면
 * 나중에 한쪽만 바뀌어 "REST로는 못 보는데 실시간 구독은 되는" 구멍이 생기기 쉽다.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class RoomService {

    /** 초대 코드가 기존 코드와 겹칠 때 다시 뽑는 최대 횟수. 31^6 ≈ 8.9억 가지라 실제로는 거의 한 번에 끝난다. */
    static final int MAX_INVITE_CODE_ATTEMPTS = 5;

    private final ChatRoomRepository roomRepository;
    private final ChatRoomMemberRepository memberRepository;
    private final AppUserRepository userRepository;
    private final InviteCodeGenerator inviteCodeGenerator;

    @Transactional
    public RoomDetailResponse createGroup(String uid, String name) {
        ChatRoom room = roomRepository.save(ChatRoom.createGroup(name, newInviteCode()));
        memberRepository.save(ChatRoomMember.join(room.getId(), uid));
        return detailOf(room);
    }

    /**
     * 초대 코드로 참여한다. 이미 멤버면 아무것도 바꾸지 않고 그 방을 돌려준다 — 오류(409)로 막으면
     * 앱이 "이미 참여한 방" 경우를 따로 처리해야 하는데, 사용자 입장에서는 결국 같은 방에 들어가는 것이다.
     *
     * @param inviteCode 대문자로 정규화된 코드 ({@link JoinRoomRequest}가 처리)
     */
    @Transactional
    public RoomDetailResponse join(String uid, String inviteCode) {
        ChatRoom room = roomRepository.findByInviteCode(inviteCode)
                .orElseThrow(RoomNotFoundException::new);
        if (!memberRepository.existsByRoomIdAndFirebaseUid(room.getId(), uid)) {
            memberRepository.save(ChatRoomMember.join(room.getId(), uid));
        }
        return detailOf(room);
    }

    public List<RoomSummaryResponse> myRooms(String uid) {
        List<ChatRoom> rooms = roomRepository.findRoomsOf(uid);
        if (rooms.isEmpty()) {
            return List.of();
        }
        Map<Long, Long> memberCounts = memberRepository
                .countByRoomIds(rooms.stream().map(ChatRoom::getId).toList()).stream()
                .collect(Collectors.toMap(
                        ChatRoomMemberRepository.RoomMemberCount::getRoomId,
                        ChatRoomMemberRepository.RoomMemberCount::getMemberCount));
        return rooms.stream()
                .map(room -> RoomSummaryResponse.of(room, memberCounts.getOrDefault(room.getId(), 0L)))
                .toList();
    }

    public RoomDetailResponse detail(String uid, Long roomId) {
        requireMember(roomId, uid);
        ChatRoom room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
        return detailOf(room);
    }

    /**
     * 멤버가 아니면 {@link RoomNotFoundException}(→ 404). 방이 아예 없는 경우도 "멤버 행이 없다"로
     * 똑같이 걸리므로 방 존재 여부를 따로 조회하지 않는다.
     */
    public void requireMember(Long roomId, String uid) {
        if (!isMember(roomId, uid)) {
            throw new RoomNotFoundException();
        }
    }

    /** 예외 없이 결과만 필요한 곳(STOMP 구독 인터셉터, 위치 릴레이)에서 쓴다. */
    public boolean isMember(Long roomId, String uid) {
        return memberRepository.existsByRoomIdAndFirebaseUid(roomId, uid);
    }

    private RoomDetailResponse detailOf(ChatRoom room) {
        List<ChatRoomMember> members = memberRepository.findByRoomIdOrderByJoinedAtAsc(room.getId());
        Map<String, AppUser> profiles = userRepository
                .findByFirebaseUidIn(members.stream().map(ChatRoomMember::getFirebaseUid).toList()).stream()
                .collect(Collectors.toMap(AppUser::getFirebaseUid, Function.identity()));
        List<MemberResponse> memberResponses = members.stream()
                .map(m -> MemberResponse.of(m, profiles.get(m.getFirebaseUid())))
                .toList();
        return RoomDetailResponse.of(room, memberResponses);
    }

    /**
     * 쓰이지 않은 초대 코드를 고른다.
     *
     * <p>Plan D 초안은 "저장해 보고 UNIQUE 위반이 나면 다시 뽑기"였지만, PostgreSQL은 트랜잭션 안에서
     * 제약 위반이 한 번 나면 그 트랜잭션 전체를 중단 상태로 만들어 이후 쿼리를 모두 거부한다.
     * 그래서 같은 트랜잭션 안에서는 재시도가 불가능하다. 대신 <b>저장 전에 존재 여부를 확인</b>하고,
     * 확인과 저장 사이에 다른 요청이 같은 코드를 쓰는 극히 드문 경우는 UNIQUE 제약이 막는다
     * (그때는 500이 나고 사용자가 다시 시도하면 된다).
     */
    private String newInviteCode() {
        for (int attempt = 0; attempt < MAX_INVITE_CODE_ATTEMPTS; attempt++) {
            String code = inviteCodeGenerator.generate();
            if (!roomRepository.existsByInviteCode(code)) {
                return code;
            }
        }
        throw new IllegalStateException("초대 코드를 " + MAX_INVITE_CODE_ATTEMPTS + "번 연속으로 중복 생성했습니다");
    }
}
