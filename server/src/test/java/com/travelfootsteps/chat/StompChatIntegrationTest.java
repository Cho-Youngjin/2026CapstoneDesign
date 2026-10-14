package com.travelfootsteps.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.messaging.converter.MappingJackson2MessageConverter;
import org.springframework.messaging.simp.stomp.StompFrameHandler;
import org.springframework.messaging.simp.stomp.StompHeaders;
import org.springframework.messaging.simp.stomp.StompSession;
import org.springframework.messaging.simp.stomp.StompSessionHandlerAdapter;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.socket.WebSocketHttpHeaders;
import org.springframework.web.socket.client.standard.StandardWebSocketClient;
import org.springframework.web.socket.messaging.WebSocketStompClient;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 실제 웹소켓으로 STOMP 클라이언트를 붙여 보는 종단 테스트 (Plan D Task 2).
 *
 * <p>단위 테스트는 인터셉터를 따로 떼어 보지만, 그것만으로는 인터셉터가 WebSocketConfig에 실제로
 * 등록돼 있는지 알 수 없다. 등록이 빠지면 단위 테스트는 모두 통과하는데 권한 검사는 통째로 사라진다.
 * 여기서는 서버를 실제 포트로 띄우고 "멤버는 메시지·위치를 받고, 비멤버는 구독 단계에서 끊긴다"를
 * 처음부터 끝까지 확인한다. (작성 시 등록을 일부러 빼 보고 이 테스트가 실패하는 것을 확인했다.)
 *
 * <p>방 만들기·메시지 보내기는 MockMvc로 하고(같은 서버 프로세스·같은 브로커), 받기만 웹소켓으로 한다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(StompChatIntegrationTest.TestBeans.class)
class StompChatIntegrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    static final String A = "token-a";
    static final String B = "token-b";
    static final String OUTSIDER = "token-outsider";

    /** 메시지가 도착하기를 기다리는 최대 시간. 보통 수십 ms면 오지만 CI 여유를 둔다. */
    static final long RECEIVE_TIMEOUT_SECONDS = 5;

    /**
     * SUBSCRIBE 프레임이 서버에 등록될 시간. 간이 브로커는 구독 완료 확인(RECEIPT)을 보내지 않으므로,
     * 구독 직후 바로 메시지를 보내면 아직 등록 전이라 놓칠 수 있다.
     */
    static final long SUBSCRIBE_SETTLE_MILLIS = 500;

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register(A, "uid-a");
            stub.register(B, "uid-b");
            stub.register(OUTSIDER, "uid-outsider");
            return stub;
        }
    }

    @LocalServerPort int port;
    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;

    private final List<StompSession> sessions = new ArrayList<>();

    @AfterEach
    void disconnectAll() {
        sessions.stream().filter(StompSession::isConnected).forEach(StompSession::disconnect);
    }

    // ───────────────────────── 헬퍼 ─────────────────────────

    private StompSession connect(String token) throws Exception {
        WebSocketStompClient client = new WebSocketStompClient(new StandardWebSocketClient());
        MappingJackson2MessageConverter converter = new MappingJackson2MessageConverter();
        converter.setObjectMapper(objectMapper);
        client.setMessageConverter(converter);

        StompHeaders connectHeaders = new StompHeaders();
        connectHeaders.add("Authorization", "Bearer " + token);
        StompSession session = client
                .connectAsync("ws://localhost:" + port + "/ws", new WebSocketHttpHeaders(), connectHeaders,
                        new StompSessionHandlerAdapter() {
                        })
                .get(RECEIVE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
        sessions.add(session);
        return session;
    }

    /** 목적지를 구독하고, 도착하는 메시지를 쌓아 둘 큐를 돌려준다. */
    private BlockingQueue<JsonNode> subscribe(StompSession session, String destination) throws InterruptedException {
        BlockingQueue<JsonNode> received = new LinkedBlockingQueue<>();
        session.subscribe(destination, new StompFrameHandler() {
            @Override
            public Type getPayloadType(StompHeaders headers) {
                return JsonNode.class;
            }

            @Override
            public void handleFrame(StompHeaders headers, Object payload) {
                received.add((JsonNode) payload);
            }
        });
        Thread.sleep(SUBSCRIBE_SETTLE_MILLIS);
        return received;
    }

    private long givenRoomWithAAndB() throws Exception {
        JsonNode room = objectMapper.readTree(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer " + A)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"종단 테스트 방\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        mockMvc.perform(post("/api/rooms/join")
                        .header("Authorization", "Bearer " + B)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("inviteCode", room.get("inviteCode").asText()))))
                .andExpect(status().isOk());
        return room.get("id").asLong();
    }

    private void sendText(String token, long roomId, String text) throws Exception {
        mockMvc.perform(post("/api/rooms/{id}/messages", roomId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("text", text))))
                .andExpect(status().isCreated());
    }

    // ───────────────────────── 테스트 ─────────────────────────

    @Test
    void 멤버는_다른_멤버가_보낸_메시지를_실시간으로_받는다() throws Exception {
        long roomId = givenRoomWithAAndB();
        BlockingQueue<JsonNode> bInbox = subscribe(connect(B), "/topic/rooms/" + roomId + "/messages");

        sendText(A, roomId, "지금 공항 도착!");

        JsonNode message = bInbox.poll(RECEIVE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
        assertThat(message).as("B가 메시지를 받아야 한다").isNotNull();
        assertThat(message.get("text").asText()).isEqualTo("지금 공항 도착!");
        assertThat(message.get("senderUid").asText()).isEqualTo("uid-a");
        assertThat(message.get("roomId").asLong()).isEqualTo(roomId);
    }

    @Test
    void 비멤버는_구독_단계에서_연결이_끊기고_메시지를_받지_못한다() throws Exception {
        long roomId = givenRoomWithAAndB();
        StompSession outsider = connect(OUTSIDER);   // 로그인 자체는 유효하다
        BlockingQueue<JsonNode> outsiderInbox = subscribe(outsider, "/topic/rooms/" + roomId + "/messages");

        sendText(A, roomId, "외부인은 보면 안 되는 메시지");

        assertThat(outsiderInbox.poll(1, TimeUnit.SECONDS)).as("비멤버에게 메시지가 가면 안 된다").isNull();
        assertThat(outsider.isConnected()).as("구독이 거부되면 서버가 연결을 끊는다").isFalse();
    }

    @Test
    void 위치는_같은_방_멤버에게만_전달된다() throws Exception {
        long roomId = givenRoomWithAAndB();
        StompSession a = connect(A);
        BlockingQueue<JsonNode> bLocations = subscribe(connect(B), "/topic/group/" + roomId + "/location");

        a.send("/app/location", Map.of("roomId", String.valueOf(roomId), "lat", 35.68, "lng", 139.76, "ts", 1L));

        JsonNode location = bLocations.poll(RECEIVE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
        assertThat(location).as("B가 A의 위치를 받아야 한다").isNotNull();
        assertThat(location.get("uid").asText()).isEqualTo("uid-a");
        assertThat(location.get("lat").asDouble()).isEqualTo(35.68);
    }

    @Test
    void 비멤버가_보낸_위치는_퍼지지_않는다() throws Exception {
        long roomId = givenRoomWithAAndB();
        StompSession outsider = connect(OUTSIDER);
        BlockingQueue<JsonNode> bLocations = subscribe(connect(B), "/topic/group/" + roomId + "/location");

        outsider.send("/app/location", Map.of("roomId", String.valueOf(roomId), "lat", 0.0, "lng", 0.0, "ts", 1L));

        assertThat(bLocations.poll(1, TimeUnit.SECONDS)).as("비멤버의 좌표가 멤버에게 가면 안 된다").isNull();
    }
}
