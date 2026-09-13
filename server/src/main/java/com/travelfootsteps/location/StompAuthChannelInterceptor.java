package com.travelfootsteps.location;

import com.travelfootsteps.auth.TokenVerifier;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.stereotype.Component;

import java.util.List;

// 왜 HTTP 필터(FirebaseAuthFilter, Phase 0)만으로는 부족한가:
// FirebaseAuthFilter는 서블릿 필터 체인에서 동작하는 OncePerRequestFilter라서, 클라이언트가
// /ws로 최초 HTTP Upgrade 요청을 보낼 때 딱 "한 번" 실행된다. 하지만 그 업그레이드가 끝나고 나면
// 하나의 TCP/WebSocket 연결 위에서 CONNECT, SUBSCRIBE, SEND, DISCONNECT 같은 여러 STOMP
// 프레임이 계속 오간다 — 이건 더 이상 서블릿 요청이 아니라 순수 메시지 스트림이라서, 서블릿
// 필터는 그 내부를 전혀 들여다보지 못한다. 즉 "핸드셰이크 시점에 인증됐다"는 사실만으로는
// "이 연결로 나중에 오는 개별 프레임이 누구 것인지"를 알 수 없다.
//
// 그래서 STOMP 레벨에는 별도의 인증 지점이 필요하다. Spring의 표준 패턴은
// ChannelInterceptor(모든 인바운드 STOMP 프레임을 가로채는 훅)를 등록해서 CONNECT 프레임에서만
// 한 번 토큰을 검증하고, 그 결과(uid)를 StompHeaderAccessor#setUser(Principal)로 세션에 "고정"하는
// 것이다. Spring의 STOMP 세션 구현은 이렇게 설정된 Principal을 세션 전체에 걸쳐 기억해 두고,
// 이후 같은 세션에서 오는 SEND/SUBSCRIBE의 @MessageMapping 메서드에 Principal 파라미터로
// 그대로 다시 넘겨준다 — 그래서 매 프레임마다 토큰을 다시 검증할 필요가 없다.
@Component
@RequiredArgsConstructor
public class StompAuthChannelInterceptor implements ChannelInterceptor {

    private static final String AUTH_HEADER = "Authorization";
    private static final String BEARER_PREFIX = "Bearer ";

    private final TokenVerifier tokenVerifier;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);

        // CONNECT 프레임에서만 인증을 수행한다. SUBSCRIBE/SEND 등 그 이후 프레임은 이미
        // CONNECT에서 세션에 고정된 Principal을 물려받으므로 여기서 다시 검사하지 않는다.
        if (accessor != null && StompCommand.CONNECT.equals(accessor.getCommand())) {
            String header = accessor.getFirstNativeHeader(AUTH_HEADER);
            if (header == null || !header.startsWith(BEARER_PREFIX)) {
                throw new StompAuthenticationException("Authorization 헤더가 없습니다");
            }
            String idToken = header.substring(BEARER_PREFIX.length());
            try {
                String uid = tokenVerifier.verifyAndGetUid(idToken);
                // setUser로 지정한 Principal은 이 STOMP 세션에 귀속된다 — 이후 같은 세션에서
                // 오는 모든 프레임의 @MessageMapping 메서드가 이 Principal을 그대로 받는다.
                accessor.setUser(new UsernamePasswordAuthenticationToken(uid, null, List.of()));
            } catch (TokenVerifier.InvalidTokenException e) {
                throw new StompAuthenticationException("유효하지 않은 토큰입니다");
            }
        }

        return message;
    }
}
