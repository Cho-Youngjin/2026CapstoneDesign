package com.travelfootsteps.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.after;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 읽음 표시 통합 테스트 (Plan D Task 7).
 *
 * <h3>합의한 동작</h3>
 * <ol>
 *     <li>읽음 위치는 멤버 행의 {@code last_read_message_id} 하나 — 메시지마다 쓰지 않는다</li>
 *     <li>위치는 줄어들지 않는다(늦게 도착한 옛 요청이 덮어쓰지 않게). 그 방의 메시지가 아니면 400</li>
 *     <li>안 읽은 수 = 내 위치보다 큰, 남이 보낸 메시지 수. 방 목록은 방이 몇 개든 쿼리 수가 같다</li>
 *     <li>위치가 실제로 바뀌면 {@code /topic/rooms/{id}/read}로 {@code {uid, lastReadMessageId}}를 퍼뜨린다</li>
 * </ol>
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@TestPropertySource(properties = "spring.jpa.properties.hibernate.generate_statistics=true")
@Import(ChatReadControllerTest.TestBeans.class)
class ChatReadControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    static final String A = "token-a";
    static final String B = "token-b";
    static final String OUTSIDER = "token-outsider";
    static final String ONE_ROOM = "token-one-room";       // 쿼리 수 비교 전용
    static final String MANY_ROOMS = "token-many-rooms";

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register(A, "uid-a");
            stub.register(B, "uid-b");
            stub.register(OUTSIDER, "uid-outsider");
            stub.register(ONE_ROOM, "uid-one-room");
            stub.register(MANY_ROOMS, "uid-many-rooms");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;
    @Autowired EntityManagerFactory entityManagerFactory;
    @MockitoSpyBean SimpMessagingTemplate messagingTemplate;

    // ───────────────────────── 헬퍼 ─────────────────────────

    private JsonNode json(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    private long givenRoom(String owner, String member) throws Exception {
        JsonNode room = json(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"읽음 테스트 방\"}"))
                .andExpect(status().isCreated()).andReturn());
        mockMvc.perform(post("/api/rooms/join")
                        .header("Authorization", "Bearer " + member)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("inviteCode", room.get("inviteCode").asText()))))
                .andExpect(status().isOk());
        return room.get("id").asLong();
    }

    private long send(String token, long roomId, String text) throws Exception {
        return json(mockMvc.perform(post("/api/rooms/{id}/messages", roomId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("text", text))))
                .andExpect(status().isCreated()).andReturn()).get("id").asLong();
    }

    private ResultActions read(String token, long roomId, long messageId) throws Exception {
        return mockMvc.perform(post("/api/rooms/{id}/read", roomId)
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"lastReadMessageId\":" + messageId + "}"));
    }

    private long unreadOf(String token, long roomId) throws Exception {
        for (JsonNode room : json(mockMvc.perform(get("/api/rooms").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andReturn())) {
            if (room.get("id").asLong() == roomId) {
                return room.get("unreadCount").asLong();
            }
        }
        throw new AssertionError("방 목록에 " + roomId + "번 방이 없다");
    }

    private Long lastReadOf(String token, long roomId, String uid) throws Exception {
        for (JsonNode member : json(mockMvc.perform(get("/api/rooms/{id}", roomId)
                .header("Authorization", "Bearer " + token)).andReturn()).get("members")) {
            if (member.get("uid").asText().equals(uid)) {
                return member.get("lastReadMessageId").isNull() ? null : member.get("lastReadMessageId").asLong();
            }
        }
        throw new AssertionError(uid + "가 멤버가 아니다");
    }

    // ───────────────────────── 안 읽은 수 ─────────────────────────

    @Test
    void 남이_보낸_메시지는_읽기_전까지_안_읽은_수에_들어가고_읽으면_0이_된다() throws Exception {
        long roomId = givenRoom(A, B);
        send(A, roomId, "하나");
        long last = send(A, roomId, "둘");

        assertThat(unreadOf(B, roomId)).isEqualTo(2);

        read(B, roomId, last).andExpect(status().isNoContent());

        assertThat(unreadOf(B, roomId)).isZero();
        assertThat(lastReadOf(A, roomId, "uid-b")).isEqualTo(last);
    }

    @Test
    void 내가_보낸_메시지는_안_읽은_수에_들어가지_않는다() throws Exception {
        long roomId = givenRoom(A, B);
        send(A, roomId, "내가 보냄");
        send(B, roomId, "B가 보냄");

        assertThat(unreadOf(A, roomId)).isEqualTo(1);
    }

    @Test
    void 일부만_읽으면_그_뒤의_메시지만_남는다() throws Exception {
        long roomId = givenRoom(A, B);
        long first = send(A, roomId, "1");
        send(A, roomId, "2");
        send(A, roomId, "3");

        read(B, roomId, first).andExpect(status().isNoContent());

        assertThat(unreadOf(B, roomId)).isEqualTo(2);
    }

    // ───────────────────────── 읽음 위치 ─────────────────────────

    @Test
    void 더_작은_id로_읽어도_위치가_줄지_않는다() throws Exception {
        long roomId = givenRoom(A, B);
        long first = send(A, roomId, "1");
        long last = send(A, roomId, "2");

        read(B, roomId, last).andExpect(status().isNoContent());
        read(B, roomId, first).andExpect(status().isNoContent());   // 늦게 도착한 옛 요청

        assertThat(lastReadOf(B, roomId, "uid-b")).isEqualTo(last);
    }

    @Test
    void 그_방의_메시지가_아니면_400() throws Exception {
        long roomId = givenRoom(A, B);
        long otherRoom = givenRoom(A, B);
        long otherMessage = send(A, otherRoom, "다른 방");

        read(B, roomId, otherMessage).andExpect(status().isBadRequest());
        read(B, roomId, 999_999).andExpect(status().isBadRequest());
        assertThat(lastReadOf(B, roomId, "uid-b")).isNull();
    }

    @Test
    void 위치가_비었거나_0_이하면_400() throws Exception {
        long roomId = givenRoom(A, B);

        mockMvc.perform(post("/api/rooms/{id}/read", roomId)
                        .header("Authorization", "Bearer " + B)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
        read(B, roomId, 0).andExpect(status().isBadRequest());
    }

    @Test
    void 비멤버는_404() throws Exception {
        long roomId = givenRoom(A, B);
        long message = send(A, roomId, "1");

        read(OUTSIDER, roomId, message).andExpect(status().isNotFound());
    }

    // ───────────────────────── 실시간 전달 ─────────────────────────

    @Test
    void 위치가_바뀌면_읽음_토픽으로_퍼뜨리고_그대로면_퍼뜨리지_않는다() throws Exception {
        long roomId = givenRoom(A, B);
        long first = send(A, roomId, "1");
        long last = send(A, roomId, "2");
        String topic = "/topic/rooms/" + roomId + "/read";

        read(B, roomId, last).andExpect(status().isNoContent());
        verify(messagingTemplate, timeout(2000)).convertAndSend(eq(topic),
                argThat((Object e) -> e instanceof ReadEvent r && r.uid().equals("uid-b") && r.lastReadMessageId() == last));

        read(B, roomId, first).andExpect(status().isNoContent());   // 줄지 않으므로 바뀐 게 없다
        verify(messagingTemplate, after(500).never()).convertAndSend(eq(topic),
                argThat((Object e) -> e instanceof ReadEvent r && r.lastReadMessageId() == first));
    }

    // ───────────────────────── 쿼리 수 ─────────────────────────

    @Test
    void 방_목록의_안_읽은_수는_방이_몇_개든_쿼리_수가_같다() throws Exception {
        long single = givenRoom(ONE_ROOM, A);
        send(A, single, "1");
        for (int i = 0; i < 4; i++) {
            long roomId = givenRoom(MANY_ROOMS, A);
            send(A, roomId, "방 " + i);
        }

        long one = statementsFor(ONE_ROOM);
        long many = statementsFor(MANY_ROOMS);

        assertThat(many).as("방마다 따로 세면(N+1) 방 수만큼 쿼리가 늘어난다").isEqualTo(one);
    }

    private long statementsFor(String token) throws Exception {
        Statistics statistics = entityManagerFactory.unwrap(SessionFactory.class).getStatistics();
        statistics.clear();
        mockMvc.perform(get("/api/rooms").header("Authorization", "Bearer " + token)).andExpect(status().isOk());
        return statistics.getPrepareStatementCount();
    }
}
