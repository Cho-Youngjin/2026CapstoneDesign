package com.travelfootsteps.chat;

import com.travelfootsteps.location.StompAuthenticationException;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.stereotype.Component;

import java.security.Principal;

/**
 * STOMP SUBSCRIBE 시점에 "그 방의 멤버인가"를 검사한다 (Plan D Task 2).
 *
 * <p>왜 필요한가: 인메모리 브로커는 목적지 문자열만 맞으면 누구에게나 메시지를 배달한다.
 * StompAuthChannelInterceptor는 CONNECT에서 "로그인한 사용자인가"만 확인하므로, 이 검사가
 * 없으면 로그인한 사람은 아무 방 id나 넣어 남의 대화와 위치를 엿들을 수 있다.
 *
 * <p>SUBSCRIBE 프레임의 Principal은 CONNECT 때 StompAuthChannelInterceptor가 세션에 고정해 둔
 * 값이다. Spring이 이 값을 이후 프레임에 인터셉터보다 먼저 붙여 두므로 두 인터셉터의 등록 순서에는
 * 의존하지 않는다(종단 테스트로 확인함). 다만 이 인터셉터가 <b>등록되지 않으면</b> 권한 검사가 통째로
 * 사라지므로, StompChatIntegrationTest가 비멤버 구독 거부를 실제 웹소켓으로 확인한다.
 *
 * <p>멤버십 규칙은 REST와 같은 {@link RoomService#isMember}를 쓴다 — 두 경로가 따로 판단하면
 * 한쪽만 바뀌어 "REST로는 못 보는데 실시간 구독은 되는" 구멍이 생길 수 있다.
 *
 * <p>한계: 구독 이후에 멤버가 방에서 빠지는 경우는 다루지 않는다. 방 나가기·강퇴 기능이 아직
 * 없으므로(Plan D 제외 범위) 지금은 일어나지 않는다.
 */
@Component
@RequiredArgsConstructor
public class RoomSubscriptionInterceptor implements ChannelInterceptor {

    private final RoomService roomService;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
        if (accessor == null || !StompCommand.SUBSCRIBE.equals(accessor.getCommand())) {
            return message;
        }

        Long roomId = RoomDestinations.subscribableRoomId(accessor.getDestination());
        if (roomId == null) {
            throw new StompAuthenticationException("구독할 수 없는 경로입니다");
        }
        Principal user = accessor.getUser();
        if (user == null || !roomService.isMember(roomId, user.getName())) {
            // 방이 없을 때와 멤버가 아닐 때를 구분하지 않는다 (REST의 404와 같은 원칙)
            throw new StompAuthenticationException("구독 권한이 없습니다");
        }
        return message;
    }
}
