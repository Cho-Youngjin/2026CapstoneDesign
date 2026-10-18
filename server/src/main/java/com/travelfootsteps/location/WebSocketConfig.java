package com.travelfootsteps.location;

import com.travelfootsteps.chat.RoomSubscriptionInterceptor;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

// @EnableWebSocketMessageBroker: STOMP-over-WebSocket 메시징 인프라(SimpAnnotationMethodMessageHandler,
// 인메모리 브로커 등)를 켠다. 이게 있어야 @Controller의 @MessageMapping과 /topic 구독이 동작한다.
//
// /ws가 SecurityConfig의 인증 대상인가: Phase 0의 SecurityConfig는 /api/**에만 인증을 요구한다.
// /ws는 이 패턴 밖이라 HTTP 레벨에서는 인증 없이 핸드셰이크(Upgrade)가 허용되지만, 실제 사용자
// 식별과 거부는 아래 StompAuthChannelInterceptor가 CONNECT 프레임에서 전담한다 — 토큰이 없거나
// 무효하면 그 시점에 연결이 즉시 끊어지므로, 결과적으로 미인증 사용자는 SEND/SUBSCRIBE까지
// 도달하지 못한다.
@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final StompAuthChannelInterceptor stompAuthChannelInterceptor;
    private final RoomSubscriptionInterceptor roomSubscriptionInterceptor;

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // SockJS 미사용 — Plan D의 Flutter STOMP 클라이언트(stomp_dart_client)가
        // 순수 WebSocket으로 직접 연결한다(SockJS 폴백/핸드셰이크 프로토콜이 필요 없다).
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*");
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        // enableSimpleBroker: 별도 메시지 브로커(RabbitMQ 등) 없이 스프링 프로세스 메모리 안에서만
        // 동작하는 브로커를 쓴다는 뜻이다. 서버가 재시작되면 모든 구독 정보가 사라지고, 위치 좌표는
        // 애초에 어디에도 저장하지 않는다(스펙 §3, §6-④) — 그래서 이 선택이 데이터 손실이 아니다.
        registry.enableSimpleBroker("/topic");
        // 클라이언트가 SEND하는 목적지 중 "/app"으로 시작하는 것만 @MessageMapping 컨트롤러로 라우팅한다.
        // 주의: 이 설정만으로는 클라이언트가 "/topic/..."에 직접 SEND하는 것을 막지 못한다(간이 브로커가 그대로
        // 구독자에게 배달한다). 그 차단은 RoomSubscriptionInterceptor가 한다 — RoomDestinations의 "/app/" 값과
        // 이 접두사를 함께 바꿔야 한다.
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        // 모든 인바운드 STOMP 프레임(CONNECT/SUBSCRIBE/SEND/...)이 이 인터셉터들을 거친다.
        // 1) StompAuthChannelInterceptor: CONNECT에서 토큰을 검증하고 uid를 세션에 고정한다.
        // 2) RoomSubscriptionInterceptor: SUBSCRIBE에서 그 uid가 해당 방의 멤버인지 확인하고,
        //    SEND는 /app/** 로 가는 것만 통과시킨다(브로커 토픽 직접 SEND 차단, Plan D Task 2).
        // 둘은 서로 다른 프레임(CONNECT / SUBSCRIBE·SEND)만 보므로 등록 순서에 의존하지 않는다 — Spring이
        // CONNECT 때 고정된 Principal을 이후 프레임에 인터셉터보다 먼저 붙여 두기 때문이다.
        // 읽는 사람이 흐름(인증 → 권한)을 따라가기 쉽도록 이 순서로 둔다.
        // 2)를 빠뜨리면 로그인한 누구나 아무 방이나 구독할 수 있게 된다 — StompChatIntegrationTest가 이를 잡는다.
        registration.interceptors(stompAuthChannelInterceptor, roomSubscriptionInterceptor);
    }
}
