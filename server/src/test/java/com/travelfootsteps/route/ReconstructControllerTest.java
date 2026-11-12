package com.travelfootsteps.route;

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
import org.springframework.test.web.servlet.ResultActions;

import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// 경로 복원 API의 JSON 계약(앱 R7·R6 분석)과 입력 검증·인증을 확인한다. RouteControllerTest와 같은 @WebMvcTest 슬라이스다.
// 서비스는 진짜를 쓰고 OsrmClient만 Mockito 가짜(모든 호출이 빈 결과 = OSRM 꺼짐)라 응답에 fallback이 붙는다.
@WebMvcTest(ReconstructController.class)
@ActiveProfiles("test")
@Import({SecurityConfig.class, ReconstructControllerTest.TestBeans.class})
class ReconstructControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        RouteReconstructionService routeReconstructionService() {
            return new RouteReconstructionService(mock(OsrmClient.class));
        }
    }

    @Autowired MockMvc mockMvc;

    private static String points(int count) {
        return IntStream.range(0, count)
                .mapToObj(i -> "{\"t\":" + (1762480000000L + i * 30000L) + ",\"lat\":" + (37.5665 + i * 0.0001)
                        + ",\"lng\":126.978,\"accuracy\":8.0,\"stepsSincePrev\":40,\"state\":\"walking\"}")
                .collect(Collectors.joining(",", "[", "]"));
    }

    private static String stays(int count) {
        return IntStream.range(0, count)
                .mapToObj(i -> "{\"arrive\":" + (1000L + i * 10) + ",\"leave\":" + (1005L + i * 10)
                        + ",\"lat\":37.5,\"lng\":127.0}")
                .collect(Collectors.joining(",", "[", "]"));
    }

    private ResultActions send(String body) throws Exception {
        return mockMvc.perform(post("/api/route/reconstruct")
                .header("Authorization", "Bearer valid-token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    @Test
    void 복원_응답은_method와_구간의_kind_coords_fallback을_담는다() throws Exception {
        send("""
                {"method":"hmm_steps",
                 "points":[{"t":1762480000000,"lat":37.5665,"lng":126.9780,"accuracy":8.0,"stepsSincePrev":null,"state":"walking"},
                           {"t":1762480060000,"lat":37.5670,"lng":126.9785,"accuracy":12.0,"stepsSincePrev":80,"state":"walking"}],
                 "stays":[],
                 "hmm":{"betaM":5.0}}""")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.method").value("hmm_steps"))
                .andExpect(jsonPath("$.segments[0].kind").value("walk"))
                .andExpect(jsonPath("$.segments[0].fallback").value(true))   // OSRM 가짜가 빈 결과
                .andExpect(jsonPath("$.segments[0].coords[0].lat").value(37.5665))
                .andExpect(jsonPath("$.segments[0].coords[1].lng").value(126.9785));
    }

    @Test
    void method를_빼면_앱_기본값_osrm_match_radius로_복원한다() throws Exception {
        send("{\"points\":" + points(2) + "}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.method").value("osrm_match_radius"))
                .andExpect(jsonPath("$.segments.length()").value(1));
    }

    @Test
    void 점이_하나뿐이면_좌표_하나짜리_구간을_fallback_false로_돌려준다() throws Exception {
        send("{\"method\":\"straight\",\"points\":" + points(1) + "}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.segments.length()").value(1))
                .andExpect(jsonPath("$.segments[0].fallback").exists())
                .andExpect(jsonPath("$.segments[0].fallback").value(false))
                .andExpect(jsonPath("$.segments[0].coords.length()").value(1));
    }

    @Test
    void 점은_2000개까지_받고_넘으면_400() throws Exception {
        send("{\"method\":\"straight\",\"points\":" + points(2000) + "}").andExpect(status().isOk());
        send("{\"method\":\"straight\",\"points\":" + points(2001) + "}").andExpect(status().isBadRequest());
    }

    @Test
    void 모르는_method나_state면_400() throws Exception {
        send("{\"method\":\"teleport\",\"points\":" + points(2) + "}").andExpect(status().isBadRequest());
        send("{\"method\":\"straight\",\"points\":[{\"t\":1,\"lat\":37.5,\"lng\":127.0,\"state\":\"flying\"}]}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void 필수_값이_빠지거나_범위를_벗어나면_400() throws Exception {
        send("{\"method\":\"straight\"}").andExpect(status().isBadRequest());   // points 없음
        send("{\"points\":[{\"lat\":37.5,\"lng\":127.0}]}").andExpect(status().isBadRequest());   // t 없음
        send("{\"points\":[{\"t\":1,\"lat\":137.5,\"lng\":127.0}]}").andExpect(status().isBadRequest());
        send("{\"points\":[{\"t\":1,\"lat\":37.5,\"lng\":127.0,\"accuracy\":-1}]}").andExpect(status().isBadRequest());
        send("{\"points\":" + points(2) + ",\"hmm\":{\"betaM\":0}}").andExpect(status().isBadRequest());
    }

    @Test
    void 머문_곳의_도착이_출발보다_늦으면_400() throws Exception {
        send("{\"points\":" + points(2) + ",\"stays\":[{\"arrive\":2000,\"leave\":1000,\"lat\":37.5,\"lng\":127.0}]}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void 머문_곳은_500개까지_받고_넘으면_400() throws Exception {
        send("{\"method\":\"straight\",\"points\":" + points(2) + ",\"stays\":" + stays(500) + "}")
                .andExpect(status().isOk());
        send("{\"method\":\"straight\",\"points\":" + points(2) + ",\"stays\":" + stays(501) + "}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void 머문_곳의_위도가_범위를_벗어나면_400() throws Exception {
        send("{\"points\":" + points(2) + ",\"stays\":[{\"arrive\":1000,\"leave\":2000,\"lat\":95,\"lng\":127.0}]}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        mockMvc.perform(post("/api/route/reconstruct")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"points\":[]}"))
                .andExpect(status().isUnauthorized());
    }
}
