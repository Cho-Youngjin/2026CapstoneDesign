package com.travelfootsteps.location;

import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.messaging.support.MessageHeaderAccessor;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

class StompAuthChannelInterceptorTest {

    StubTokenVerifier verifier;
    StompAuthChannelInterceptor interceptor;
    MessageChannel channel;

    @BeforeEach
    void setUp() {
        verifier = new StubTokenVerifier();
        verifier.register("valid-token", "uid-123");
        interceptor = new StompAuthChannelInterceptor(verifier);
        channel = mock(MessageChannel.class);
    }

    private Message<byte[]> connectMessage(String authorizationHeader) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
        if (authorizationHeader != null) {
            accessor.addNativeHeader("Authorization", authorizationHeader);
        }
        accessor.setLeaveMutable(true);
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    @Test
    void 유효한_토큰의_CONNECT는_uid를_Principal로_설정한다() {
        Message<byte[]> message = connectMessage("Bearer valid-token");

        Message<?> result = interceptor.preSend(message, channel);

        StompHeaderAccessor resultAccessor = MessageHeaderAccessor.getAccessor(result, StompHeaderAccessor.class);
        assertThat(resultAccessor.getUser()).isNotNull();
        assertThat(resultAccessor.getUser().getName()).isEqualTo("uid-123");
    }

    @Test
    void 토큰이_없는_CONNECT는_예외를_던진다() {
        Message<byte[]> message = connectMessage(null);

        assertThatThrownBy(() -> interceptor.preSend(message, channel))
                .isInstanceOf(StompAuthenticationException.class);
    }

    @Test
    void 유효하지_않은_토큰의_CONNECT는_예외를_던진다() {
        Message<byte[]> message = connectMessage("Bearer garbage");

        assertThatThrownBy(() -> interceptor.preSend(message, channel))
                .isInstanceOf(StompAuthenticationException.class);
    }

    @Test
    void CONNECT가_아닌_프레임은_그대로_통과시킨다() {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.SEND);
        accessor.setLeaveMutable(true);
        Message<byte[]> message = MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());

        Message<?> result = interceptor.preSend(message, channel);

        assertThat(result).isSameAs(message);
    }
}
