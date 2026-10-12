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

import java.util.HashMap;
import java.util.Map;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.matchesPattern;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 그룹 채팅방 생성·참여·조회와 프로필 API 통합 테스트 (Plan D Task 1).
 *
 * <h3>합의한 동작 (2026-10-11)</h3>
 * <ol>
 *     <li>이미 멤버인 사람이 다시 참여하면 오류가 아니라 200으로 그 방을 돌려준다 (중복 멤버 없음)</li>
 *     <li>방 이름은 앞뒤 공백을 잘라 저장하고, 자른 뒤 비어 있으면 400</li>
 *     <li>방 목록은 Task 1에서는 만든 순서 최신순 (Task 2에서 "최근 메시지순"으로 바뀐다)</li>
 *     <li>방 상세의 멤버는 참여한 순서 — 만든 사람이 항상 맨 앞</li>
 *     <li>멤버가 아닌 방은 "없는 방"과 똑같이 404 (방의 존재 여부를 흘리지 않는다)</li>
 * </ol>
 *
 * <h3>테스트 간 데이터 격리</h3>
 * TripControllerTest와 같이 @Transactional 롤백을 쓰지 않으므로 DB가 테스트끼리 공유된다.
 * 그래서 "목록 개수"처럼 다른 테스트의 데이터에 영향을 받는 검증은 <b>그 테스트 전용 사용자</b>
 * (LIST_*, EMPTY)로만 한다. 나머지 테스트는 매번 방을 새로 만들어 그 방 id로만 확인한다.
 * C의 프로필은 어떤 테스트에서도 올리지 않는다 — "프로필 없는 멤버" 테스트가 C를 쓴다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(RoomControllerTest.TestBeans.class)
class RoomControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    /** 초대 코드 형식 — InviteCodeGeneratorTest.VALID_CODE와 같다. */
    private static final String INVITE_CODE_PATTERN = "[A-HJKMNP-Z2-9]{6}";

    // 일반 테스트용 사용자
    static final String A = "token-a";
    static final String B = "token-b";
    static final String C = "token-c";
    // 목록 개수를 세는 테스트 전용 사용자 — 다른 테스트가 이 사용자로 방을 만들지 않는다
    static final String LIST_A = "token-list-a";
    static final String LIST_C = "token-list-c";
    static final String EMPTY = "token-empty";

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register(A, "uid-a");
            stub.register(B, "uid-b");
            stub.register(C, "uid-c");
            stub.register(LIST_A, "uid-list-a");
            stub.register(LIST_C, "uid-list-c");
            stub.register(EMPTY, "uid-empty");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;

    // ───────────────────────── 요청 헬퍼 ─────────────────────────

    private ResultActions createRoom(String token, String name) throws Exception {
        return mockMvc.perform(post("/api/rooms")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("name", name))));
    }

    private ResultActions join(String token, String inviteCode) throws Exception {
        return mockMvc.perform(post("/api/rooms/join")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(Map.of("inviteCode", inviteCode))));
    }

    private ResultActions myRooms(String token) throws Exception {
        return mockMvc.perform(get("/api/rooms")
                .header("Authorization", "Bearer " + token));
    }

    private ResultActions roomDetail(String token, long roomId) throws Exception {
        return mockMvc.perform(get("/api/rooms/{id}", roomId)
                .header("Authorization", "Bearer " + token));
    }

    private ResultActions putProfile(String token, String displayName, String photoUrl) throws Exception {
        // Map.of는 null 값을 허용하지 않으므로 photoUrl이 null일 수 있는 경우를 위해 HashMap을 쓴다
        Map<String, Object> body = new HashMap<>();
        body.put("displayName", displayName);
        body.put("photoUrl", photoUrl);
        return mockMvc.perform(put("/api/me/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(body)));
    }

    private JsonNode json(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    /** 방을 만들고 응답 바디를 돌려준다 — given 단계에서 방 id와 초대 코드를 얻는 용도. */
    private JsonNode givenRoom(String token, String name) throws Exception {
        return json(createRoom(token, name).andExpect(status().isCreated()).andReturn());
    }

    // ───────────────────────── 방 만들기 POST /api/rooms ─────────────────────────

    @Test
    void 방을_만들면_만든_사람이_멤버가_된다() throws Exception {
        createRoom(A, "도쿄 여행")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNumber())
                .andExpect(jsonPath("$.type").value("GROUP"))
                .andExpect(jsonPath("$.name").value("도쿄 여행"))
                .andExpect(jsonPath("$.inviteCode").value(matchesPattern(INVITE_CODE_PATTERN)))
                .andExpect(jsonPath("$.members", hasSize(1)))
                .andExpect(jsonPath("$.members[0].uid").value("uid-a"));
    }

    @Test
    void 방_이름의_앞뒤_공백은_잘라서_저장한다() throws Exception {
        createRoom(A, "  도쿄 여행  ")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("도쿄 여행"));
    }

    @Test
    void 방_이름이_비어_있으면_400() throws Exception {
        createRoom(A, "").andExpect(status().isBadRequest());
        createRoom(A, "   ").andExpect(status().isBadRequest());   // 자른 뒤 비어 있는 경우
    }

    @Test
    void 방_이름은_50자까지_허용하고_51자부터_400() throws Exception {
        createRoom(A, "가".repeat(50)).andExpect(status().isCreated());
        createRoom(A, "가".repeat(51)).andExpect(status().isBadRequest());
    }

    @Test
    void 로그인하지_않으면_401() throws Exception {
        mockMvc.perform(post("/api/rooms")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"도쿄 여행\"}"))
                .andExpect(status().isUnauthorized());
    }

    // ───────────────────────── 참여하기 POST /api/rooms/join ─────────────────────────

    @Test
    void 초대_코드로_참여하면_멤버가_늘어난다() throws Exception {
        JsonNode room = givenRoom(A, "오사카");

        join(B, room.get("inviteCode").asText())
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(room.get("id").asLong()))
                .andExpect(jsonPath("$.members", hasSize(2)))
                .andExpect(jsonPath("$.members[0].uid").value("uid-a"))   // 만든 사람이 맨 앞
                .andExpect(jsonPath("$.members[1].uid").value("uid-b"));
    }

    @Test
    void 이미_멤버인_사람이_다시_참여해도_중복되지_않는다() throws Exception {
        JsonNode room = givenRoom(A, "삿포로");
        String code = room.get("inviteCode").asText();
        join(B, code).andExpect(status().isOk());

        join(B, code)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.members", hasSize(2)));
        // 만든 사람이 자기 방 코드로 참여해도 같다
        join(A, code)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.members", hasSize(2)));
    }

    @Test
    void 초대_코드는_소문자로_입력해도_참여된다() throws Exception {
        JsonNode room = givenRoom(A, "후쿠오카");

        join(B, room.get("inviteCode").asText().toLowerCase())
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(room.get("id").asLong()));
    }

    @Test
    void 없는_초대_코드는_404() throws Exception {
        // 31자 집합에 있는 글자라 형식은 맞지만 실제로는 없는 코드
        join(B, "ZZZZZZ").andExpect(status().isNotFound());
    }

    // ───────────────────────── 조회 GET /api/rooms, GET /api/rooms/{id} ─────────────────────────

    @Test
    void 내_방_목록에는_내가_속한_방만_최신순으로_나온다() throws Exception {
        givenRoom(LIST_A, "첫 번째");
        givenRoom(LIST_A, "두 번째");
        givenRoom(LIST_C, "남의 방");

        myRooms(LIST_A)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].name").value("두 번째"))
                .andExpect(jsonPath("$[1].name").value("첫 번째"))
                .andExpect(jsonPath("$[0].memberCount").value(1))
                // 아직 기능이 없는 값은 비어 있다 (RoomSummaryResponse 주석 참고)
                .andExpect(jsonPath("$[0].unreadCount").value(0))
                .andExpect(jsonPath("$[0].lastMessagePreview").value(nullValue()))
                .andExpect(jsonPath("$[0].dmPeer").value(nullValue()));
    }

    @Test
    void 방이_하나도_없으면_빈_목록이다() throws Exception {
        myRooms(EMPTY)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void 멤버가_아니면_방_상세를_볼_수_없다() throws Exception {
        long roomId = givenRoom(A, "교토").get("id").asLong();

        roomDetail(C, roomId).andExpect(status().isNotFound());   // 403이 아니다
        roomDetail(A, roomId).andExpect(status().isOk());         // 대조: 멤버는 볼 수 있다
    }

    @Test
    void 없는_방_id는_404() throws Exception {
        roomDetail(A, 999_999_999L).andExpect(status().isNotFound());
    }

    // ───────────────────────── 프로필 PUT /api/me/profile ─────────────────────────

    @Test
    void 프로필을_올리면_방_상세에_이름과_사진이_나온다() throws Exception {
        putProfile(A, "유저", "https://example.com/a.png").andExpect(status().isNoContent());
        long roomId = givenRoom(A, "나고야").get("id").asLong();

        roomDetail(A, roomId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.members[0].displayName").value("유저"))
                .andExpect(jsonPath("$.members[0].photoUrl").value("https://example.com/a.png"));
    }

    @Test
    void 프로필을_다시_올리면_덮어쓴다() throws Exception {
        putProfile(B, "이전 이름", null).andExpect(status().isNoContent());
        putProfile(B, "새 이름", null).andExpect(status().isNoContent());
        JsonNode room = givenRoom(A, "오키나와");
        join(B, room.get("inviteCode").asText()).andExpect(status().isOk());

        roomDetail(A, room.get("id").asLong())
                .andExpect(jsonPath("$.members[1].uid").value("uid-b"))
                .andExpect(jsonPath("$.members[1].displayName").value("새 이름"));
    }

    @Test
    void 프로필을_올리지_않은_멤버는_이름이_null이다() throws Exception {
        JsonNode room = givenRoom(A, "고베");
        join(C, room.get("inviteCode").asText()).andExpect(status().isOk());

        roomDetail(A, room.get("id").asLong())
                .andExpect(status().isOk())   // app_user 행이 없어도 500이 나면 안 된다
                .andExpect(jsonPath("$.members[1].uid").value("uid-c"))
                .andExpect(jsonPath("$.members[1].displayName").value(nullValue()))
                .andExpect(jsonPath("$.members[1].photoUrl").value(nullValue()));
    }
}
