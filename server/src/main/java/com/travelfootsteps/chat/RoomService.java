package com.travelfootsteps.chat;

import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
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
    private final DmRoomCreator dmRoomCreator;

    /**
     * 1:1 DM을 연다(Plan D Task 5). 이미 있으면 그 방을, 없으면 새로 만들어 돌려준다.
     *
     * <ul>
     *     <li>자기 자신 → {@link SelfDmException}(400)</li>
     *     <li>같은 그룹 멤버가 아님(없는 사용자 포함) → {@link RoomNotFoundException}(404). 스펙 §6-④의 "낯선 사용자
     *     연락 제외" — uid만 알면 아무에게나 DM을 걸 수 있으면 그게 곧 낯선 사람 연락이다.</li>
     * </ul>
     *
     * <p>{@code @Transactional(propagation = NOT_SUPPORTED)}: 이 메서드는 트랜잭션 없이 돈다(클래스에 붙은
     * readOnly 트랜잭션을 쓰지 않는다). 방 만들기는 {@link DmRoomCreator}가 자기 트랜잭션에서 하는데, 바깥에도
     * 트랜잭션이 있으면 요청 하나가 DB 연결을 두 개 붙잡는다. 동시에 여러 요청이 오면 연결 풀이 바닥나 서로
     * 기다리다 멈출 수 있어서, 조회는 각각 짧게 끝내고 연결을 바로 돌려준다.
     */
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public RoomDetailResponse openDm(String uid, String peerUid) {
        if (uid.equals(peerUid)) {
            throw new SelfDmException();
        }
        if (!memberRepository.shareGroup(uid, peerUid)) {
            throw new RoomNotFoundException();
        }
        String dmKey = ChatRoom.dmKeyOf(uid, peerUid);
        ChatRoom room = roomRepository.findByDmKey(dmKey)
                .orElseGet(() -> createDmOrFindExisting(dmKey, uid, peerUid));
        // 열쇠가 겹치지 않게 만들었지만, 찾은 방이 정말 내 방인지 한 번 더 확인한다 — 어긋나면 남의 DM 멤버를
        // 그대로 보여 주게 되므로 마지막 안전장치로 둔다.
        requireMember(room.getId(), uid);
        return detailOf(room);
    }

    /**
     * 두 사람이 동시에 열어 상대 요청이 먼저 방을 만들었으면 UNIQUE(dm_key) 위반이 난다. 그때는 그 방을 다시 찾아
     * 돌려준다 — 사용자에게는 오류가 아니라 같은 DM에 들어가는 것이다.
     */
    private ChatRoom createDmOrFindExisting(String dmKey, String uid, String peerUid) {
        try {
            return dmRoomCreator.create(dmKey, uid, peerUid);
        } catch (DataIntegrityViolationException e) {
            return roomRepository.findByDmKey(dmKey).orElseThrow(() -> e);
        }
    }

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
        Map<Long, MemberResponse> dmPeers = dmPeersOf(uid,
                rooms.stream().filter(r -> r.getType() == RoomType.DM).map(ChatRoom::getId).toList());
        return rooms.stream()
                .map(room -> RoomSummaryResponse.of(room, memberCounts.getOrDefault(room.getId(), 0L),
                        dmPeers.get(room.getId())))
                .toList();
    }

    /**
     * DM 방마다 "나 아닌 쪽" 멤버와 그 프로필. 앱이 DM을 상대 이름·사진으로 보여 주려고 쓴다.
     * 방이 몇 개든 멤버 조회 한 번, 프로필 조회 한 번으로 끝낸다(N+1을 피한다).
     */
    private Map<Long, MemberResponse> dmPeersOf(String uid, Collection<Long> dmRoomIds) {
        if (dmRoomIds.isEmpty()) {
            return Map.of();
        }
        List<ChatRoomMember> peers = memberRepository.findByRoomIdIn(dmRoomIds).stream()
                .filter(m -> !m.getFirebaseUid().equals(uid))
                .toList();
        Map<String, AppUser> profiles = userRepository
                .findByFirebaseUidIn(peers.stream().map(ChatRoomMember::getFirebaseUid).toList()).stream()
                .collect(Collectors.toMap(AppUser::getFirebaseUid, Function.identity()));
        return peers.stream().collect(Collectors.toMap(
                ChatRoomMember::getRoomId,
                m -> MemberResponse.of(m, profiles.get(m.getFirebaseUid())),
                (first, second) -> first)); // DM은 두 사람뿐이라 겹치지 않지만, 혹시 몰라 먼저 것을 쓴다
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
