package com.travelfootsteps.translate;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.auth.SecurityConfig;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// @WebMvcTest(TranslateController.class): 전체 애플리케이션 컨텍스트(DB, JPA, Flyway 등)를
// 띄우지 않고 웹 계층(이 컨트롤러와 관련 MVC 인프라)만 가볍게 띄운다. 이 앱은 DataSource/JPA
// 자동 설정이 무조건 켜져 있어서(country/trip 등 다른 도메인이 DB를 쓰므로), @SpringBootTest를
// 그대로 쓰면 실제 PostgreSQL(Testcontainers)이 필요해진다. 이 컨트롤러는 DB를 전혀 쓰지 않는
// 순수 프록시이므로 그런 무게가 필요 없다 — HealthControllerTest와 같은 패턴이다.
// SecurityConfig는 @WebMvcTest가 자동으로 로딩하지 않으므로(SecurityConfig.java 클래스 주석
// 참고) @Import로 직접 끼워 넣어야 401 응답까지 실제로 검증할 수 있다.
@WebMvcTest(TranslateController.class)
@ActiveProfiles("test")
@Import({SecurityConfig.class, TranslateControllerTest.TestBeans.class})
class TranslateControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        TranslationClient translationClient() {
            TranslationClient mock = mock(TranslationClient.class);
            when(mock.translate(eq("안녕하세요"), eq("en"), isNull()))
                    .thenReturn(new TranslationResult("Hello", "ko"));
            when(mock.translate(eq("안녕"), eq("fr"), eq("ko")))
                    .thenReturn(new TranslationResult("Bonjour", null));
            return mock;
        }
    }

    @Autowired MockMvc mockMvc;
    @Autowired ObjectMapper objectMapper;

    @Test
    void sourceLanguage_생략시_자동감지_결과를_포함해_반환한다() throws Exception {
        var request = new TranslateRequest("안녕하세요", "en", null);

        mockMvc.perform(post("/api/translate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.translatedText").value("Hello"))
                .andExpect(jsonPath("$.detectedSourceLanguage").value("ko"));
    }

    @Test
    void sourceLanguage_지정시_그대로_전달한다() throws Exception {
        var request = new TranslateRequest("안녕", "fr", "ko");

        mockMvc.perform(post("/api/translate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.translatedText").value("Bonjour"));
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        var request = new TranslateRequest("안녕", "en", null);

        mockMvc.perform(post("/api/translate")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isUnauthorized());
    }

    // TranslateRequest.text에 붙은 @NotBlank(+ 컨트롤러의 @Valid)가 실제로 검사되는지 확인한다.
    // 공백 문자열은 "값이 있긴 하지만 비어 있다"는 경우라 null 체크만으로는 못 잡아낸다.
    @Test
    void text가_공백이면_400() throws Exception {
        var request = new TranslateRequest("   ", "en", null);

        mockMvc.perform(post("/api/translate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest());
    }
}
