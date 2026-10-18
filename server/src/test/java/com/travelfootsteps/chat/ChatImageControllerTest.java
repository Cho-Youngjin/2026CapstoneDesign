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
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 채팅 사진 전송·내려받기 통합 테스트 (Plan D Task 6).
 *
 * <h3>합의한 동작</h3>
 * <ol>
 *     <li>JPEG·PNG·WEBP만 받는다. 형식은 파일 앞부분 바이트로 판정한다 — 이름·Content-Type은 믿지 않는다(위장하면 415)</li>
 *     <li>5MB를 넘으면 413</li>
 *     <li>멤버만 올리고 내려받는다. 비멤버·다른 방의 메시지·사진이 아닌 메시지는 전부 404</li>
 *     <li>올리면 IMAGE 메시지가 저장되고 텍스트처럼 실시간으로 퍼진다. 방 목록 미리보기는 "사진"</li>
 * </ol>
 *
 * <p>사진은 테스트마다 새로 만든 임시 디렉터리에 저장한다(실제 서버의 ./data를 건드리지 않게).
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(ChatImageControllerTest.TestBeans.class)
class ChatImageControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    static final Path IMAGE_DIR = createTempDir();

    @DynamicPropertySource
    static void imageDir(DynamicPropertyRegistry registry) {
        registry.add("chat.image-dir", IMAGE_DIR::toString);
    }

    private static Path createTempDir() {
        try {
            return Files.createTempDirectory("chat-images-test");
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    static final String A = "token-a";
    static final String B = "token-b";
    static final String OUTSIDER = "token-outsider";

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

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;
    @MockitoSpyBean SimpMessagingTemplate messagingTemplate;

    // 앞부분 바이트(매직 넘버) 뒤에 아무 바이트나 붙인 가짜 그림. 서버는 앞부분만 본다.
    static final byte[] JPEG = bytes(new int[]{0xFF, 0xD8, 0xFF, 0xE0}, 64);
    static final byte[] PNG = bytes(new int[]{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}, 64);
    static final byte[] WEBP = bytes(new int[]{'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P'}, 64);

    private static byte[] bytes(int[] head, int total) {
        byte[] b = new byte[total];
        Arrays.fill(b, (byte) 7);
        for (int i = 0; i < head.length; i++) {
            b[i] = (byte) head[i];
        }
        return b;
    }

    // ───────────────────────── 헬퍼 ─────────────────────────

    private JsonNode json(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    private long givenRoomWithAAndB() throws Exception {
        JsonNode room = json(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer " + A)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"사진 테스트 방\"}"))
                .andExpect(status().isCreated()).andReturn());
        mockMvc.perform(post("/api/rooms/join")
                        .header("Authorization", "Bearer " + B)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("inviteCode", room.get("inviteCode").asText()))))
                .andExpect(status().isOk());
        return room.get("id").asLong();
    }

    private ResultActions upload(String token, long roomId, String filename, String contentType, byte[] body)
            throws Exception {
        return mockMvc.perform(multipart("/api/rooms/{id}/images", roomId)
                .file(new MockMultipartFile("file", filename, contentType, body))
                .header("Authorization", "Bearer " + token));
    }

    private JsonNode uploaded(String token, long roomId, byte[] body) throws Exception {
        return json(upload(token, roomId, "photo.jpg", "image/jpeg", body)
                .andExpect(status().isCreated()).andReturn());
    }

    private ResultActions download(String token, long roomId, long messageId) throws Exception {
        return mockMvc.perform(get("/api/rooms/{id}/images/{messageId}", roomId, messageId)
                .header("Authorization", "Bearer " + token));
    }

    private long storedFileCount() throws IOException {
        try (Stream<Path> files = Files.list(IMAGE_DIR)) {
            return files.count();
        }
    }

    // ───────────────────────── 올리기 ─────────────────────────

    @Test
    void JPEG를_올리면_사진_메시지가_생기고_실시간으로_퍼진다() throws Exception {
        long roomId = givenRoomWithAAndB();

        JsonNode message = uploaded(A, roomId, JPEG);

        long id = message.get("id").asLong();
        assertThat(message.get("type").asText()).isEqualTo("IMAGE");
        assertThat(message.get("senderUid").asText()).isEqualTo("uid-a");
        assertThat(message.get("text").isNull()).isTrue();
        assertThat(message.get("imageUrl").asText()).isEqualTo("/api/rooms/" + roomId + "/images/" + id);
        // 브로드캐스트는 커밋 뒤에 따로 나간다(ChatMessageBroadcaster).
        verify(messagingTemplate, timeout(2000)).convertAndSend(eq("/topic/rooms/" + roomId + "/messages"),
                argThat((Object m) -> m instanceof MessageResponse r && r.id() == id && r.type() == MessageType.IMAGE));

        mockMvc.perform(get("/api/rooms/{id}/messages", roomId).header("Authorization", "Bearer " + B))
                .andExpect(jsonPath("$[0].id").value(id))
                .andExpect(jsonPath("$[0].imageUrl").value("/api/rooms/" + roomId + "/images/" + id));
        mockMvc.perform(get("/api/rooms").header("Authorization", "Bearer " + B))
                .andExpect(jsonPath("$[?(@.id == " + roomId + ")].lastMessagePreview").value("사진"));
    }

    @Test
    void 이름이나_Content_Type이_아니라_내용으로_형식을_판정한다() throws Exception {
        long roomId = givenRoomWithAAndB();

        // 텍스트 파일을 .jpg·image/jpeg로 위장해도 거부한다.
        upload(A, roomId, "evil.jpg", "image/jpeg", "<html>not an image</html>".getBytes())
                .andExpect(status().isUnsupportedMediaType());
        // 반대로 이름·Content-Type이 엉뚱해도 내용이 PNG면 받는다.
        upload(A, roomId, "noext", "application/octet-stream", PNG).andExpect(status().isCreated());
    }

    @Test
    void PNG와_WEBP도_받고_내려받을_때_맞는_Content_Type을_준다() throws Exception {
        long roomId = givenRoomWithAAndB();
        long png = uploaded(A, roomId, PNG).get("id").asLong();
        long webp = uploaded(A, roomId, WEBP).get("id").asLong();

        download(B, roomId, png).andExpect(status().isOk()).andExpect(content().contentType("image/png"));
        download(B, roomId, webp).andExpect(status().isOk()).andExpect(content().contentType("image/webp"));
    }

    @Test
    void 파일이_5MB를_넘으면_413이고_아무것도_남기지_않는다() throws Exception {
        long roomId = givenRoomWithAAndB();
        long before = storedFileCount();
        byte[] tooBig = bytes(new int[]{0xFF, 0xD8, 0xFF, 0xE0}, 5 * 1024 * 1024 + 1);

        upload(A, roomId, "big.jpg", "image/jpeg", tooBig).andExpect(status().isPayloadTooLarge());

        assertThat(storedFileCount()).isEqualTo(before);
        mockMvc.perform(get("/api/rooms/{id}/messages", roomId).header("Authorization", "Bearer " + A))
                .andExpect(jsonPath("$").isEmpty());
    }

    @Test
    void 빈_파일이나_파일이_없으면_400() throws Exception {
        long roomId = givenRoomWithAAndB();

        upload(A, roomId, "empty.jpg", "image/jpeg", new byte[0]).andExpect(status().isBadRequest());
        mockMvc.perform(multipart("/api/rooms/{id}/images", roomId).header("Authorization", "Bearer " + A))
                .andExpect(status().isBadRequest());
    }

    @Test
    void 비멤버는_올릴_수_없고_아무것도_남기지_않는다() throws Exception {
        long roomId = givenRoomWithAAndB();
        long before = storedFileCount();

        upload(OUTSIDER, roomId, "photo.jpg", "image/jpeg", JPEG).andExpect(status().isNotFound());

        assertThat(storedFileCount()).isEqualTo(before);
    }

    // ───────────────────────── 다시 보내기(clientId) ─────────────────────────

    private ResultActions uploadWithClientId(String token, long roomId, String clientId) throws Exception {
        return mockMvc.perform(multipart("/api/rooms/{id}/images", roomId)
                .file(new MockMultipartFile("file", "photo.jpg", "image/jpeg", JPEG))
                .param("clientId", clientId)
                .header("Authorization", "Bearer " + token));
    }

    @Test
    void 같은_clientId로_다시_보내면_새로_저장하지_않고_처음_메시지를_돌려준다() throws Exception {
        // 서버는 저장했는데 응답이 끊겨 앱이 [다시 시도]한 경우 — 같은 사진이 두 장 올라가면 안 된다.
        long roomId = givenRoomWithAAndB();
        long before = storedFileCount();

        long first = json(uploadWithClientId(A, roomId, "c3f1a2b4-0001").andExpect(status().isCreated()).andReturn())
                .get("id").asLong();
        long second = json(uploadWithClientId(A, roomId, "c3f1a2b4-0001").andExpect(status().isCreated()).andReturn())
                .get("id").asLong();

        assertThat(second).isEqualTo(first);
        assertThat(storedFileCount()).isEqualTo(before + 1);
        mockMvc.perform(get("/api/rooms/{id}/messages", roomId).header("Authorization", "Bearer " + A))
                .andExpect(jsonPath("$.length()").value(1));
    }

    @Test
    void clientId가_같아도_보낸_사람이나_방이_다르면_다른_사진이다() throws Exception {
        long roomId = givenRoomWithAAndB();
        long otherRoomId = givenRoomWithAAndB();

        long a = json(uploadWithClientId(A, roomId, "same-id").andReturn()).get("id").asLong();
        long b = json(uploadWithClientId(B, roomId, "same-id").andReturn()).get("id").asLong();
        long other = json(uploadWithClientId(A, otherRoomId, "same-id").andReturn()).get("id").asLong();

        assertThat(Set.of(a, b, other)).hasSize(3);
    }

    @Test
    void clientId는_64자_이하의_영문_숫자_하이픈만_받는다() throws Exception {
        long roomId = givenRoomWithAAndB();

        uploadWithClientId(A, roomId, "x".repeat(65)).andExpect(status().isBadRequest());
        uploadWithClientId(A, roomId, "../evil").andExpect(status().isBadRequest());
    }

    // ───────────────────────── 내려받기 ─────────────────────────

    @Test
    void 멤버는_올린_바이트_그대로_내려받는다() throws Exception {
        long roomId = givenRoomWithAAndB();
        long id = uploaded(A, roomId, JPEG).get("id").asLong();

        download(B, roomId, id)
                .andExpect(status().isOk())
                .andExpect(content().contentType("image/jpeg"))
                .andExpect(content().bytes(JPEG))
                // 같은 사진을 다시 그릴 때 앱이 매번 받지 않게 하되, 공용 캐시(프록시)에는 남기지 않는다.
                .andExpect(header().string("Cache-Control", "max-age=86400, private"));
    }

    @Test
    void 비멤버는_내려받을_수_없다() throws Exception {
        long roomId = givenRoomWithAAndB();
        long id = uploaded(A, roomId, JPEG).get("id").asLong();

        download(OUTSIDER, roomId, id).andExpect(status().isNotFound());
    }

    @Test
    void 다른_방의_메시지_id나_사진이_아닌_메시지는_404() throws Exception {
        long roomId = givenRoomWithAAndB();
        long otherRoomId = givenRoomWithAAndB();
        long photoInOther = uploaded(A, otherRoomId, JPEG).get("id").asLong();
        long textId = json(mockMvc.perform(post("/api/rooms/{id}/messages", roomId)
                        .header("Authorization", "Bearer " + A)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"text\":\"글자 메시지\"}"))
                .andExpect(status().isCreated()).andReturn()).get("id").asLong();

        // 내가 두 방 모두의 멤버여도, 경로의 방과 메시지의 방이 다르면 없는 것으로 본다.
        download(A, roomId, photoInOther).andExpect(status().isNotFound());
        download(A, roomId, textId).andExpect(status().isNotFound());
        download(A, roomId, 999_999).andExpect(status().isNotFound());
    }
}
