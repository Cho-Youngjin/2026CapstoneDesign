package com.travelfootsteps.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
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
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 메시지 보내기·조회 API 통합 테스트 (Plan D Task 2).
 *
 * <p>실시간 전송은 {@link SimpMessagingTemplate}을 목으로 바꿔 "어느 목적지로 무엇을 보냈는지"만
 * 확인한다. 실제 웹소켓으로 구독자에게 도착하는지는 StompChatIntegrationTest가 본다.
 *
 * <p>RoomControllerTest처럼 테스트끼리 DB를 공유하므로, 매 테스트가 새 방을 만들어 그 방에서만 확인한다.
 * 방 목록 순서를 보는 테스트만 전용 사용자(LIST)를 쓴다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(MessageControllerTest.TestBeans.class)
class MessageControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    static final String A = "token-a";
    static final String B = "token-b";
    static final String OUTSIDER = "token-outsider";
    static final String LIST = "token-list";

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register(A, "uid-a");
            stub.register(B, "uid-b");
            stub.register(OUTSIDER, "uid-outsider");
            stub.register(LIST, "uid-list");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;
    @MockitoBean SimpMessagingTemplate messagingTemplate;

    @BeforeEach
    void resetBroadcasts() {
        clearInvocations(messagingTemplate);
    }

    // ───────────────────────── 헬퍼 ─────────────────────────

    private JsonNode json(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    /** A가 방을 만들고 B를 참여시킨 뒤 방 id를 돌려준다. */
    private long givenRoomWithAAndB(String name) throws Exception {
        JsonNode room = json(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer " + A)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("name", name))))
                .andExpect(status().isCreated()).andReturn());
        mockMvc.perform(post("/api/rooms/join")
                        .header("Authorization", "Bearer " + B)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("inviteCode", room.get("inviteCode").asText()))))
                .andExpect(status().isOk());
        return room.get("id").asLong();
    }

    private long givenRoomOf(String token, String name) throws Exception {
        return json(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("name", name))))
                .andExpect(status().isCreated()).andReturn()).get("id").asLong();
    }

    private ResultActions send(String token, long roomId, String text) throws Exception {
        return mockMvc.perform(post("/api/rooms/{id}/messages", roomId)
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("text", text))));
    }

    private long sendAndGetId(String token, long roomId, String text) throws Exception {
        return json(send(token, roomId, text).andExpect(status().isCreated()).andReturn()).get("id").asLong();
    }

    private ResultActions list(String token, long roomId, String query) throws Exception {
        return mockMvc.perform(get("/api/rooms/{id}/messages" + query, roomId)
                .header("Authorization", "Bearer " + token));
    }

    // ───────────────────────── 보내기 ─────────────────────────

    @Test
    void 메시지를_보내면_저장되고_id와_시각을_돌려준다() throws Exception {
        long roomId = givenRoomWithAAndB("도쿄");

        send(A, roomId, "  안녕하세요  ")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNumber())
                .andExpect(jsonPath("$.roomId").value(roomId))
                .andExpect(jsonPath("$.senderUid").value("uid-a"))
                .andExpect(jsonPath("$.type").value("TEXT"))
                .andExpect(jsonPath("$.text").value("안녕하세요"))   // 앞뒤 공백 제거
                .andExpect(jsonPath("$.imageUrl").value(nullValue()))
                .andExpect(jsonPath("$.createdAt").value(notNullValue()));
    }

    @Test
    void 보낸_메시지를_그_방_토픽으로_한_번_브로드캐스트한다() throws Exception {
        long roomId = givenRoomWithAAndB("오사카");

        long messageId = sendAndGetId(A, roomId, "출발합니다");

        // REST 응답과 같은 모양(MessageResponse)이 같은 id로 나가야 앱이 중복을 걸러낼 수 있다
        ArgumentCaptor<Object> payload = ArgumentCaptor.forClass(Object.class);
        verify(messagingTemplate).convertAndSend(eq("/topic/rooms/" + roomId + "/messages"), payload.capture());
        assertThat(payload.getValue()).isInstanceOf(MessageResponse.class);
        MessageResponse broadcast = (MessageResponse) payload.getValue();
        assertThat(broadcast.id()).isEqualTo(messageId);
        assertThat(broadcast.senderUid()).isEqualTo("uid-a");
        assertThat(broadcast.text()).isEqualTo("출발합니다");
    }

    @Test
    void 공백뿐이거나_1000자를_넘는_메시지는_400이고_브로드캐스트하지_않는다() throws Exception {
        long roomId = givenRoomWithAAndB("교토");

        send(A, roomId, "   ").andExpect(status().isBadRequest());
        send(A, roomId, "가".repeat(1001)).andExpect(status().isBadRequest());
        send(A, roomId, "가".repeat(1000)).andExpect(status().isCreated());   // 경계값

        // 성공한 1000자 메시지 한 번만 나간다
        verify(messagingTemplate).convertAndSend(anyString(), any(Object.class));
    }

    @Test
    void 멤버가_아니면_보낼_수_없고_브로드캐스트도_없다() throws Exception {
        long roomId = givenRoomWithAAndB("삿포로");

        send(OUTSIDER, roomId, "몰래 보내기").andExpect(status().isNotFound());

        verify(messagingTemplate, never()).convertAndSend(anyString(), any(Object.class));
    }

    @Test
    void 없는_방으로는_보낼_수_없다() throws Exception {
        send(A, 999_999_999L, "어디로").andExpect(status().isNotFound());
    }

    // ───────────────────────── 조회 ─────────────────────────

    @Test
    void 메시지_목록은_최신순이다() throws Exception {
        long roomId = givenRoomWithAAndB("후쿠오카");
        sendAndGetId(A, roomId, "첫째");
        sendAndGetId(B, roomId, "둘째");
        sendAndGetId(A, roomId, "셋째");

        list(B, roomId, "")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(3)))
                .andExpect(jsonPath("$[0].text").value("셋째"))
                .andExpect(jsonPath("$[1].text").value("둘째"))
                .andExpect(jsonPath("$[1].senderUid").value("uid-b"))
                .andExpect(jsonPath("$[2].text").value("첫째"));
    }

    @Test
    void before로_더_오래된_메시지를_이어서_가져온다() throws Exception {
        long roomId = givenRoomWithAAndB("나고야");
        for (int i = 1; i <= 5; i++) {
            sendAndGetId(A, roomId, "메시지" + i);
        }

        // 첫 페이지: 최신 2개 (5, 4)
        JsonNode firstPage = json(list(A, roomId, "?size=2")
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].text").value("메시지5"))
                .andExpect(jsonPath("$[1].text").value("메시지4"))
                .andReturn());
        long oldestOnFirstPage = firstPage.get(1).get("id").asLong();

        // 다음 페이지: 그보다 오래된 2개 (3, 2)
        list(A, roomId, "?size=2&before=" + oldestOnFirstPage)
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].text").value("메시지3"))
                .andExpect(jsonPath("$[1].text").value("메시지2"));
    }

    @Test
    void 한_번에_최대_50개까지만_준다() throws Exception {
        long roomId = givenRoomWithAAndB("고베");
        for (int i = 0; i < 52; i++) {
            sendAndGetId(A, roomId, "m" + i);
        }

        list(A, roomId, "?size=500").andExpect(jsonPath("$", hasSize(50)));
        list(A, roomId, "").andExpect(jsonPath("$", hasSize(30)));   // 기본값
    }

    @Test
    void 멤버가_아니면_메시지를_볼_수_없다() throws Exception {
        long roomId = givenRoomWithAAndB("오키나와");
        sendAndGetId(A, roomId, "비밀 이야기");

        list(OUTSIDER, roomId, "").andExpect(status().isNotFound());
    }

    @Test
    void 메시지가_없는_방은_빈_목록이다() throws Exception {
        long roomId = givenRoomWithAAndB("히로시마");

        list(A, roomId, "").andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(0)));
    }

    // ───────────────────────── 방 목록에 반영 ─────────────────────────

    @Test
    void 메시지를_보내면_방_목록의_미리보기와_순서가_바뀐다() throws Exception {
        long older = givenRoomOf(LIST, "먼저 만든 방");
        long newer = givenRoomOf(LIST, "나중에 만든 방");

        // 메시지가 없을 때는 만든 순서 최신순
        mockMvc.perform(get("/api/rooms").header("Authorization", "Bearer " + LIST))
                .andExpect(jsonPath("$[0].id").value(newer))
                .andExpect(jsonPath("$[1].id").value(older));

        // 먼저 만든 방에 메시지가 오면 그 방이 맨 위로 올라온다
        sendAndGetId(LIST, older, "가".repeat(150));

        mockMvc.perform(get("/api/rooms").header("Authorization", "Bearer " + LIST))
                .andExpect(jsonPath("$[0].id").value(older))
                .andExpect(jsonPath("$[0].lastMessagePreview").value("가".repeat(100)))   // 100자로 자름
                .andExpect(jsonPath("$[0].lastMessageAt").value(notNullValue()))
                .andExpect(jsonPath("$[1].id").value(newer))
                .andExpect(jsonPath("$[1].lastMessagePreview").value(nullValue()));
    }
}
