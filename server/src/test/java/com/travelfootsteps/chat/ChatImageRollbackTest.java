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
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 파일은 저장됐는데 메시지 저장이 실패하는 경우(Plan D Task 6 Step 2) — 트랜잭션이 롤백되면 방금 저장한 파일도
 * 지워져야 한다. 방 정보 갱신 쿼리를 일부러 실패시켜 만든다. 다른 테스트에 영향을 주지 않게 클래스를 따로 둔다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(ChatImageRollbackTest.TestBeans.class)
class ChatImageRollbackTest {

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
            return Files.createTempDirectory("chat-images-rollback");
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("token-a", "uid-a");
            return stub;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;
    @MockitoSpyBean ChatRoomRepository roomRepository;

    @Test
    void 메시지_저장이_실패하면_방금_저장한_파일도_지운다() throws Exception {
        JsonNode room = objectMapper.readTree(mockMvc.perform(post("/api/rooms")
                        .header("Authorization", "Bearer token-a")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"롤백 테스트\"}"))
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString());
        long roomId = room.get("id").asLong();
        doThrow(new IllegalStateException("DB 실패 흉내"))
                .when(roomRepository).recordLastMessage(anyLong(), anyLong(), anyString(), any());

        // 처리되지 않은 예외는 MockMvc에서 그대로 던져진다(실제 서버에서는 500).
        assertThatThrownBy(() -> mockMvc.perform(multipart("/api/rooms/{id}/images", roomId)
                .file(new MockMultipartFile("file", "photo.jpg", "image/jpeg",
                        new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0, 1, 2}))
                .header("Authorization", "Bearer token-a")));

        try (Stream<Path> files = Files.list(IMAGE_DIR)) {
            assertThat(files).as("롤백되면 파일도 남지 않아야 한다").isEmpty();
        }
        mockMvc.perform(get("/api/rooms/{id}/messages", roomId).header("Authorization", "Bearer token-a"))
                .andExpect(jsonPath("$").isEmpty());
    }
}
