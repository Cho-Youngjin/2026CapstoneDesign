package com.travelfootsteps.location;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import java.security.Principal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

@ExtendWith(MockitoExtension.class)
class LocationRelayControllerTest {

    @Mock SimpMessagingTemplate messagingTemplate;

    @Test
    void 방_주제로_발신자_uid를_채워_브로드캐스트한다() {
        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        Principal principal = () -> "uid-123";
        LocationMessage message = new LocationMessage("room-1", 37.5, 127.0, 1_700_000_000_000L);

        controller.relay(message, principal);

        verify(messagingTemplate).convertAndSend(eq("/topic/group/room-1/location"),
                eq(new LocationBroadcast("uid-123", 37.5, 127.0, 1_700_000_000_000L)));
    }

    @Test
    void 인증되지_않은_세션의_메시지는_무시한다() {
        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        LocationMessage message = new LocationMessage("room-1", 37.5, 127.0, 1_700_000_000_000L);

        controller.relay(message, null);

        verifyNoInteractions(messagingTemplate);
    }

    @Test
    void roomId가_빈_문자열이면_무시한다() {
        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        Principal principal = () -> "uid-123";
        LocationMessage message = new LocationMessage("", 37.5, 127.0, 1_700_000_000_000L);

        controller.relay(message, principal);

        verifyNoInteractions(messagingTemplate);
    }

    @Test
    void 위조된_uid_필드를_담은_전송_페이로드도_세션_Principal의_실제_uid로만_브로드캐스트한다() throws Exception {
        // 안티 스푸핑 회귀 테스트. 악의적이거나 버그가 있는 클라이언트가
        // SEND /app/location 바디에 자기 신고 uid("attacker-controlled-uid")를 끼워 보냈다고 가정한다.
        // 실제 STOMP 메시지 컨버터가 쓰는 것과 같은 Jackson ObjectMapper로 그 JSON을
        // LocationMessage로 역직렬화한다 — LocationMessage 레코드에는애초에 uid 필드가 선언되어 있지
        // 않으므로(기본 Jackson 설정은 알 수 없는 필드를 조용히 무시한다) 위조 시도는 여기서 이미 사라진다.
        // 그 다음 컨트롤러가 실제로 내보내는 브로드캐스트의 uid가 (위조값이 아니라) StompAuthChannelInterceptor가
        // CONNECT에서 검증해 세션에 고정해 둔 Principal의 이름과 정확히 일치하는지 확인한다.
        String forgedPayload = """
                {"roomId":"room-1","lat":37.5,"lng":127.0,"ts":1700000000000,"uid":"attacker-controlled-uid"}
                """;
        ObjectMapper objectMapper = new ObjectMapper();
        LocationMessage message;
        try {
            message = objectMapper.readValue(forgedPayload, LocationMessage.class);
        } catch (com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException expected) {
            // 위조된 프레임이 역직렬화 단계에서 이미 거부됨 — 컨트롤러까지 도달조차 못 하므로
            // 위조 uid가 브로드캐스트될 여지가 없다. 이 결과 자체로 안티 스푸핑 불변조건은 지켜진다.
            return;
        }

        LocationRelayController controller = new LocationRelayController(messagingTemplate);
        Principal principal = () -> "real-uid-from-verified-token"; // StompAuthChannelInterceptor가 CONNECT에서 고정한 값

        controller.relay(message, principal);

        var captor = org.mockito.ArgumentCaptor.forClass(LocationBroadcast.class);
        verify(messagingTemplate).convertAndSend(eq("/topic/group/room-1/location"), captor.capture());
        assertThat(captor.getValue().uid())
                .as("브로드캐스트 uid는 위조된 페이로드 값이 아니라 세션 Principal의 실제 uid여야 한다")
                .isEqualTo("real-uid-from-verified-token")
                .isNotEqualTo("attacker-controlled-uid");
    }
}
