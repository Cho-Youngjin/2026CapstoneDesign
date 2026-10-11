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
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.fail;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

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
 * (아래 LIST_*, EMPTY 토큰)로만 한다. 나머지 테스트는 매번 방을 새로 만들어 그 방 id로만 확인한다.
 *
 * TODO(구현): 각 테스트의 fail(...)을 지우고 given/when/then 주석대로 채운다.
 *   요청을 보내는 헬퍼(createRoom, join 등)는 이미 완성돼 있으니 그대로 쓰면 된다.
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

    // ───────────────────────── 요청 헬퍼 (완성) ─────────────────────────

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
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("displayName", displayName);
        body.put("photoUrl", photoUrl);
        return mockMvc.perform(put("/api/me/profile")
                .header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(body)));
    }

    /** 응답 바디를 JsonNode로. 예: json(createRoom(A, "도쿄").andReturn()).get("id").asLong() */
    private JsonNode json(org.springframework.test.web.servlet.MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    // ───────────────────────── 방 만들기 POST /api/rooms ─────────────────────────

    @Test
    void 방을_만들면_만든_사람이_멤버가_된다() throws Exception {
        // when:  A가 "도쿄 여행" 방을 만든다
        // then:  201
        //        type == "GROUP", name == "도쿄 여행"
        //        inviteCode가 6자리
        //        members가 1명이고 그 uid가 "uid-a"
        fail("TODO");
    }

    @Test
    void 방_이름의_앞뒤_공백은_잘라서_저장한다() throws Exception {
        // when:  A가 "  도쿄 여행  " 으로 만든다
        // then:  201, name == "도쿄 여행"
        fail("TODO");
    }

    @Test
    void 방_이름이_비어_있으면_400() throws Exception {
        // when/then:  "" → 400
        //             "   " (공백만) → 400  ← 자른 뒤 비어 있는 경우
        fail("TODO");
    }

    @Test
    void 방_이름은_50자까지_허용하고_51자부터_400() throws Exception {
        // 경계값 테스트
        // when/then:  "가".repeat(50) → 201
        //             "가".repeat(51) → 400
        fail("TODO");
    }

    @Test
    void 로그인하지_않으면_401() throws Exception {
        // when:  Authorization 헤더 없이 POST /api/rooms
        // then:  401
        // 주의:  createRoom 헬퍼는 헤더를 붙이므로 여기서는 mockMvc.perform(post(...))를 직접 쓴다
        fail("TODO");
    }

    // ───────────────────────── 참여하기 POST /api/rooms/join ─────────────────────────

    @Test
    void 초대_코드로_참여하면_멤버가_늘어난다() throws Exception {
        // given: A가 방을 만들고 inviteCode를 얻는다
        // when:  B가 그 코드로 참여
        // then:  200
        //        응답의 id가 A가 만든 방 id와 같다
        //        members가 2명, 순서는 [uid-a, uid-b] (참여 순서 — 만든 사람이 맨 앞)
        fail("TODO");
    }

    @Test
    void 이미_멤버인_사람이_다시_참여해도_중복되지_않는다() throws Exception {
        // given: A가 방을 만들고 B가 한 번 참여
        // when:  B가 같은 코드로 한 번 더 참여
        // then:  200 (409 같은 오류가 아니다)
        //        members는 여전히 2명
        // 추가로: 만든 사람 A가 자기 방 코드로 참여해도 200, 멤버 수 그대로인지 확인하면 좋다
        fail("TODO");
    }

    @Test
    void 초대_코드는_소문자로_입력해도_참여된다() throws Exception {
        // given: A가 방을 만든다
        // when:  B가 inviteCode.toLowerCase()로 참여
        // then:  200, 같은 방 id
        fail("TODO");
    }

    @Test
    void 없는_초대_코드는_404() throws Exception {
        // when:  B가 "ZZZZZZ"로 참여
        //        (31자 집합에 있는 글자라 형식은 맞지만 실제로는 없는 코드)
        // then:  404
        fail("TODO");
    }

    // ───────────────────────── 조회 GET /api/rooms, GET /api/rooms/{id} ─────────────────────────

    @Test
    void 내_방_목록에는_내가_속한_방만_최신순으로_나온다() throws Exception {
        // ※ 다른 테스트의 영향을 받지 않도록 LIST_A, LIST_C 전용 사용자만 쓴다
        // given: LIST_A가 "첫 번째", "두 번째" 방을 차례로 만든다
        //        LIST_C가 "남의 방"을 만든다
        // when:  LIST_A로 GET /api/rooms
        // then:  200, 2개
        //        [0].name == "두 번째", [1].name == "첫 번째"  (만든 순서 최신순)
        //        "남의 방"은 없다
        fail("TODO");
    }

    @Test
    void 방이_하나도_없으면_빈_목록이다() throws Exception {
        // when:  EMPTY로 GET /api/rooms
        // then:  200, 빈 배열 []
        fail("TODO");
    }

    @Test
    void 멤버가_아니면_방_상세를_볼_수_없다() throws Exception {
        // given: A가 방을 만든다
        // when:  C가 그 방 id로 GET /api/rooms/{id}
        // then:  404  ← 403이 아니다. 방이 있다는 사실 자체를 알려주지 않는다
        // 대조:  같은 요청을 A가 하면 200이어야 한다
        fail("TODO");
    }

    @Test
    void 없는_방_id는_404() throws Exception {
        // when:  A가 GET /api/rooms/999999999
        // then:  404
        fail("TODO");
    }

    // ───────────────────────── 프로필 PUT /api/me/profile ─────────────────────────

    @Test
    void 프로필을_올리면_방_상세에_이름과_사진이_나온다() throws Exception {
        // given: A가 프로필("성주", "https://example.com/a.png")을 올린다 → 204
        //        A가 방을 만든다
        // when:  방 상세 조회
        // then:  members[0].displayName == "성주"
        //        members[0].photoUrl == "https://example.com/a.png"
        fail("TODO");
    }

    @Test
    void 프로필을_다시_올리면_덮어쓴다() throws Exception {
        // given: B가 "이전 이름"으로 올린 뒤 "새 이름"으로 다시 올린다
        //        A가 방을 만들고 B가 참여한다
        // when:  방 상세 조회
        // then:  B의 displayName == "새 이름"
        fail("TODO");
    }

    @Test
    void 프로필을_올리지_않은_멤버는_이름이_null이다() throws Exception {
        // given: C는 프로필을 한 번도 올리지 않았다 (이 클래스에서 C의 프로필을 올리는 테스트가 없어야 한다)
        //        A가 방을 만들고 C가 참여한다
        // when:  방 상세 조회
        // then:  200 (500이 나면 안 된다 — app_user 행이 없는 경우를 처리해야 한다)
        //        C의 displayName이 null
        fail("TODO");
    }
}
