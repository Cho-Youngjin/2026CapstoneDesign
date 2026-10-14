package com.travelfootsteps.chat;

import com.travelfootsteps.location.StompAuthenticationException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;

import java.security.Principal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

/**
 * SUBSCRIBE 권한 검사 단위 테스트. 멤버십 판단은 RoomService 목으로 대신한다 —
 * "멤버면 통과, 아니면 거부"라는 인터셉터의 규칙만 본다.
 */
@ExtendWith(MockitoExtension.class)
class RoomSubscriptionInterceptorTest {

    @Mock RoomService roomService;

    RoomSubscriptionInterceptor interceptor;
    final MessageChannel channel = mock(MessageChannel.class);
    final Principal member = () -> "uid-member";
    final Principal outsider = () -> "uid-outsider";

    @BeforeEach
    void setUp() {
        interceptor = new RoomSubscriptionInterceptor(roomService);
        lenient().when(roomService.isMember(7L, "uid-member")).thenReturn(true);
        lenient().when(roomService.isMember(7L, "uid-outsider")).thenReturn(false);
    }

    private Message<byte[]> frame(StompCommand command, String destination, Principal user) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(command);
        accessor.setDestination(destination);
        accessor.setUser(user);
        accessor.setLeaveMutable(true);
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    @ParameterizedTest
    @ValueSource(strings = {"/topic/rooms/7/messages", "/topic/rooms/7/read", "/topic/group/7/location"})
    void 멤버는_자기_방의_세_가지_토픽을_구독할_수_있다(String destination) {
        Message<byte[]> message = frame(StompCommand.SUBSCRIBE, destination, member);

        assertThat(interceptor.preSend(message, channel)).isSameAs(message);
    }

    @ParameterizedTest
    @ValueSource(strings = {"/topic/rooms/7/messages", "/topic/rooms/7/read", "/topic/group/7/location"})
    void 멤버가_아니면_구독을_거부한다(String destination) {
        assertThatThrownBy(() -> interceptor.preSend(frame(StompCommand.SUBSCRIBE, destination, outsider), channel))
                .isInstanceOf(StompAuthenticationException.class);
    }

    @Test
    void Principal이_없으면_구독을_거부한다() {
        assertThatThrownBy(() -> interceptor.preSend(
                frame(StompCommand.SUBSCRIBE, "/topic/rooms/7/messages", null), channel))
                .isInstanceOf(StompAuthenticationException.class);
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "/topic/rooms/abc/messages",   // 숫자가 아닌 방 id
            "/topic/rooms/7/unknown",      // 모르는 하위 토픽
            "/topic/rooms/7/messages/x",   // 뒤에 덧붙인 경로
            "/topic/other",                // 방과 무관한 토픽
            "/topic/rooms//messages",      // 빈 방 id
            "/app/location"                // 브로커 토픽이 아닌 경로
    })
    void 허용_목록에_없는_경로는_멤버_확인_없이_거부한다(String destination) {
        assertThatThrownBy(() -> interceptor.preSend(frame(StompCommand.SUBSCRIBE, destination, member), channel))
                .isInstanceOf(StompAuthenticationException.class);
        verifyNoInteractions(roomService);
    }

    @Test
    void SUBSCRIBE가_아닌_프레임은_검사하지_않는다() {
        // SEND 등은 각 컨트롤러가 처리한다 (예: LocationRelayController의 멤버 확인)
        Message<byte[]> send = frame(StompCommand.SEND, "/app/location", outsider);

        assertThat(interceptor.preSend(send, channel)).isSameAs(send);
        verifyNoInteractions(roomService);
    }
}
