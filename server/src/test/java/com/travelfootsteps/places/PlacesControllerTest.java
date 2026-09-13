package com.travelfootsteps.places;

import com.travelfootsteps.auth.SecurityConfig;
import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// TranslateControllerTest와 같은 이유로 @WebMvcTest + @Import(SecurityConfig.class)를 쓴다 —
// 이 컨트롤러도 DB를 쓰지 않는 순수 프록시라 Testcontainers/PostgreSQL이 필요 없다.
@WebMvcTest(PlacesController.class)
@ActiveProfiles("test")
@Import({SecurityConfig.class, PlacesControllerTest.TestBeans.class})
class PlacesControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        PlacesClient placesClient() {
            PlacesClient mock = mock(PlacesClient.class);
            when(mock.nearby(eq(37.5), eq(127.0), eq(500), eq(PlaceCategory.RESTAURANT)))
                    .thenReturn(List.of(new PlaceResult("p1", "테스트 식당", PlaceCategory.RESTAURANT,
                            "서울", 37.5, 127.0)));
            return mock;
        }
    }

    @Autowired MockMvc mockMvc;

    @Test
    void 카테고리로_주변정보를_조회한다() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .header("Authorization", "Bearer valid-token")
                        .param("lat", "37.5").param("lng", "127.0")
                        .param("radius", "500").param("category", "RESTAURANT"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].name").value("테스트 식당"))
                .andExpect(jsonPath("$[0].category").value("RESTAURANT"));
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .param("lat", "37.5").param("lng", "127.0").param("category", "RESTAURANT"))
                .andExpect(status().isUnauthorized());
    }

    // category는 PlaceCategory enum 파라미터라, 정의되지 않은 값("FOO")이 오면 스프링이
    // 바인딩 단계에서 실패한다(MethodArgumentTypeMismatchException) — 별도 처리 코드 없이도
    // 400으로 응답하는지 확인한다.
    @Test
    void 존재하지_않는_카테고리면_400() throws Exception {
        mockMvc.perform(get("/api/places/nearby")
                        .header("Authorization", "Bearer valid-token")
                        .param("lat", "37.5").param("lng", "127.0").param("category", "FOO"))
                .andExpect(status().isBadRequest());
    }
}
