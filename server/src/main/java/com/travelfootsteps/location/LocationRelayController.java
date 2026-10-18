package com.travelfootsteps.location;

import com.travelfootsteps.chat.RoomDestinations;
import com.travelfootsteps.chat.RoomService;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.security.Principal;

/**
 * 그룹 실시간 위치공유의 서버 릴레이. 좌표를 저장하지 않고 같은 방을 구독 중인
 * 클라이언트에게만 즉시 전달한다(스펙 §3, §6-④ — 5초 간격 좌표를 계속 저장하면
 * 쓰기가 금방 쌓이므로 애초에 저장하지 않는 설계다).
 *
 * 발신자 uid는 클라이언트가 자기 신고로 보내지 않는다(LocationMessage에는 uid 필드
 * 자체가 없다) — StompAuthChannelInterceptor가 STOMP CONNECT 시점에 Firebase 토큰을
 * 검증해 세션에 고정해 둔 Principal에서 서버가 직접 채운다. 이 메서드 시그니처의
 * Principal 파라미터는 Spring Messaging이 그 세션 고정값을 자동으로 주입해 준 것이며,
 * 클라이언트가 이 값을 조작할 수 있는 경로는 없다(위조 방지).
 *
 * 그룹 멤버십 검사 (Plan D Task 2에서 추가): roomId는 채팅방 id(chat_room.id)이고, 그 방의
 * 멤버만 좌표를 보낼 수 있다. 받는 쪽은 RoomSubscriptionInterceptor가 같은 규칙으로
 * 구독을 막는다. Plan A Task 10은 당시 멤버 정보가 서버에 없어 "roomId를 아는 로그인 사용자"까지만
 * 보장했는데, 채팅방 멤버 테이블이 생기면서 그 잔여 리스크를 닫았다.
 */
@Controller
@RequiredArgsConstructor
public class LocationRelayController {

    private final SimpMessagingTemplate messagingTemplate;
    private final RoomService roomService;

    @MessageMapping("/location")
    public void relay(LocationMessage message, Principal principal) {
        if (principal == null) {
            return; // 인증되지 않은 프레임(이론상 인터셉터가 이미 걸렀어야 함)은 조용히 버린다
        }
        Long roomId = RoomDestinations.parseRoomId(message.roomId());
        if (roomId == null || !roomService.isMember(roomId, principal.getName())) {
            // 방 정보가 없거나 숫자가 아니거나, 그 방의 멤버가 아니면 버린다.
            // 오류를 돌려주지 않는 이유: STOMP SEND에는 응답이 없고, 5초마다 오는 좌표라
            // 하나를 버려도 사용자 경험에 영향이 없다.
            return;
        }
        LocationBroadcast broadcast = new LocationBroadcast(
                principal.getName(), message.lat(), message.lng(), message.ts());
        messagingTemplate.convertAndSend(RoomDestinations.location(roomId), broadcast);
    }
}
