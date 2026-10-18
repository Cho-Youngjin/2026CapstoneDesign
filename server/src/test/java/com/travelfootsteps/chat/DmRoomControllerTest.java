package com.travelfootsteps.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
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
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 1:1 DM 통합 테스트 (Plan D Task 5).
 *
 * <h3>합의한 동작</h3>
 * <ol>
 *     <li>DM은 <b>같은 그룹의 멤버끼리만</b> 열 수 있다(스펙 §6-④ 낯선 사용자 연락 제외). 아니면 404</li>
 *     <li>같은 두 사람의 DM은 하나뿐이다 — 누가 먼저 열든, 몇 번을 열든, 동시에 열든 같은 방</li>
 *     <li>자기 자신에게는 400</li>
 *     <li>DM 방은 이름·초대 코드가 없다(그래서 코드로 참여할 수 없다)</li>
 *     <li>방 목록에서 DM은 상대 프로필을 {@code dmPeer}로 준다</li>
 * </ol>
 *
 * <p>테스트끼리 DB를 공유하므로(롤백 없음) "같은 그룹이 아니다"·"목록" 검증은 그 테스트 전용 사용자로 한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(DmRoomControllerTest.TestBeans.class)
class DmRoomControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    static final String A = "token-a";
    static final String B = "token-b";
    static final String OUTSIDER = "token-outsider";
    static final String LONER = "token-loner";      // 어떤 그룹에도 들어가지 않는다
    static final String LIST_A = "token-list-a";    // 목록 테스트 전용
    static final String LIST_B = "token-list-b";
    static final String RACE_A = "token-race-a";    // 동시성 테스트 전용
    static final String RACE_B = "token-race-b";

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register(A, "uid-a");
            stub.register(B, "uid-b");
            stub.register(OUTSIDER, "uid-outsider");
            stub.register(LONER, "uid-loner");
            stub.register(LIST_A, "uid-list-a");
            stub.register(LIST_B, "uid-list-b");
            stub.register(RACE_A, "uid-race-a");
            stub.register(RACE_B, "uid-race-b");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;

    // ───────────────────────── 요청 헬퍼 ─────────────────────────

    private ResultActions openDm(String token, String peerUid) throws Exception {
        return mockMvc.perform(post("/api/rooms/dm")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("peerUid", peerUid))));
    }

    private JsonNode json(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    /** 두 사람이 함께 있는 그룹을 만든다. */
    private void givenSameGroup(String owner, String member) throws Exception {
        JsonNode room = json(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"DM 테스트 그룹\"}"))
                .andExpect(status().isCreated()).andReturn());
        mockMvc.perform(post("/api/rooms/join")
                        .header("Authorization", "Bearer " + member)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("inviteCode", room.get("inviteCode").asText()))))
                .andExpect(status().isOk());
    }

    private long dmIdOf(String token, String peerUid) throws Exception {
        return json(openDm(token, peerUid).andExpect(status().isOk()).andReturn()).get("id").asLong();
    }

    // ───────────────────────── POST /api/rooms/dm ─────────────────────────

    @Test
    void 같은_그룹_멤버에게_DM을_열면_두_사람만_있는_DM_방이_생긴다() throws Exception {
        givenSameGroup(A, B);

        openDm(A, "uid-b")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.type").value("DM"))
                .andExpect(jsonPath("$.name").value(nullValue()))
                .andExpect(jsonPath("$.inviteCode").value(nullValue()))   // 코드로 참여할 수 없다
                .andExpect(jsonPath("$.members", hasSize(2)))
                // 두 사람이 같은 순간에 들어가 참여 시각이 같을 수 있으므로 순서는 보지 않는다.
                .andExpect(jsonPath("$.members[*].uid", containsInAnyOrder("uid-a", "uid-b")));
    }

    @Test
    void 같은_두_사람이면_누가_몇_번_열어도_같은_방이다() throws Exception {
        givenSameGroup(A, B);
        long first = dmIdOf(A, "uid-b");

        assertThat(dmIdOf(A, "uid-b")).isEqualTo(first);
        assertThat(dmIdOf(B, "uid-a")).isEqualTo(first);
    }

    @Test
    void 같은_그룹이_아니면_404() throws Exception {
        givenSameGroup(A, B);

        openDm(A, "uid-loner").andExpect(status().isNotFound());
        openDm(LONER, "uid-a").andExpect(status().isNotFound());
        openDm(A, "uid-nobody").andExpect(status().isNotFound());   // 없는 사용자도 똑같이
    }

    @Test
    void 자기_자신에게는_400() throws Exception {
        givenSameGroup(A, B);

        openDm(A, "uid-a").andExpect(status().isBadRequest());
    }

    @Test
    void 상대_uid가_비어_있으면_400() throws Exception {
        openDm(A, "  ").andExpect(status().isBadRequest());
    }

    @Test
    void DM_방은_두_사람_외에는_볼_수_없다() throws Exception {
        givenSameGroup(A, B);
        givenSameGroup(A, OUTSIDER);   // 같은 그룹에 있어도 남의 DM은 못 본다
        long dmId = dmIdOf(A, "uid-b");

        mockMvc.perform(get("/api/rooms/{id}", dmId).header("Authorization", "Bearer " + OUTSIDER))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/rooms/{id}/messages", dmId).header("Authorization", "Bearer " + OUTSIDER))
                .andExpect(status().isNotFound());
    }

    @Test
    void DM에서도_메시지를_주고받는다() throws Exception {
        givenSameGroup(A, B);
        long dmId = dmIdOf(A, "uid-b");

        mockMvc.perform(post("/api/rooms/{id}/messages", dmId)
                        .header("Authorization", "Bearer " + B)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"text\":\"내일 몇 시에 만나?\"}"))
                .andExpect(status().isCreated());
        mockMvc.perform(get("/api/rooms/{id}/messages", dmId).header("Authorization", "Bearer " + A))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].text").value("내일 몇 시에 만나?"));
    }

    // ───────────────────────── 방 목록의 dmPeer ─────────────────────────

    @Test
    void 방_목록에서_DM은_상대_프로필을_dmPeer로_준다() throws Exception {
        mockMvc.perform(put("/api/me/profile")
                        .header("Authorization", "Bearer " + LIST_B)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"displayName\":\"민준\",\"photoUrl\":\"https://example.com/b.png\"}"))
                .andExpect(status().isNoContent());
        givenSameGroup(LIST_A, LIST_B);
        long dmId = dmIdOf(LIST_A, "uid-list-b");

        JsonNode rooms = json(mockMvc.perform(get("/api/rooms").header("Authorization", "Bearer " + LIST_A))
                .andExpect(status().isOk()).andReturn());

        assertThat(rooms).hasSize(2);
        for (JsonNode room : rooms) {
            if (room.get("id").asLong() == dmId) {
                assertThat(room.get("type").asText()).isEqualTo("DM");
                assertThat(room.get("memberCount").asLong()).isEqualTo(2);
                assertThat(room.get("dmPeer").get("uid").asText()).isEqualTo("uid-list-b");
                assertThat(room.get("dmPeer").get("displayName").asText()).isEqualTo("민준");
                assertThat(room.get("dmPeer").get("photoUrl").asText()).isEqualTo("https://example.com/b.png");
            } else {
                assertThat(room.get("type").asText()).isEqualTo("GROUP");
                assertThat(room.get("dmPeer").isNull()).isTrue();
            }
        }
    }

    // ───────────────────────── 동시에 열기 ─────────────────────────

    @Test
    void 두_사람이_동시에_서로에게_DM을_열어도_방은_하나다() throws Exception {
        givenSameGroup(RACE_A, RACE_B);
        int requests = 8;
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService pool = Executors.newFixedThreadPool(requests);
        try {
            List<Future<Long>> results = new ArrayList<>();
            for (int i = 0; i < requests; i++) {
                boolean fromA = i % 2 == 0;
                Callable<Long> call = () -> {
                    start.await();
                    return fromA ? dmIdOf(RACE_A, "uid-race-b") : dmIdOf(RACE_B, "uid-race-a");
                };
                results.add(pool.submit(call));
            }
            start.countDown();

            Set<Long> ids = new HashSet<>();
            for (Future<Long> result : results) {
                ids.add(result.get(30, TimeUnit.SECONDS));
            }
            assertThat(ids).hasSize(1);
        } finally {
            pool.shutdownNow();
        }
    }
}
