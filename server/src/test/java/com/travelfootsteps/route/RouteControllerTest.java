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

import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// 앱(Flutter)과의 JSON 계약(필드 이름, 실패 시 응답 모양)과 인증/입력 검증을 확인한다.
// PlacesControllerTest와 같은 이유로 @WebMvcTest 슬라이스(DB 불필요)를 쓴다.
@WebMvcTest(RouteController.class)
@ActiveProfiles("test")
@Import({SecurityConfig.class, RouteControllerTest.TestBeans.class})
class RouteControllerTest {

    private static final GeoPoint SNAPPED = new GeoPoint(35.681198, 139.767109);

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }

        @Bean
        OsrmClient osrmClient() {
            OsrmClient mock = mock(OsrmClient.class);
            when(mock.nearest(eq("JP"), eq(new GeoPoint(35.6812, 139.7671)), anyDouble()))
                    .thenReturn(Optional.of(SNAPPED));
            when(mock.nearest(eq("JP"), eq(new GeoPoint(35.0, 140.5)), anyDouble()))
                    .thenReturn(Optional.empty());
            when(mock.match(eq("KR"), any())).thenReturn(List.of());
            return mock;
        }

        @Bean
        OverseasWalkService overseasWalkService() {
            OverseasWalkService mock = mock(OverseasWalkService.class);
            when(mock.walk(eq("JP"), any(), any(), any())).thenReturn(new OverseasWalkResponse(
                    true, false, List.of(SNAPPED), SNAPPED, null,
                    new WalkState(10.0, 20.0, List.of(SNAPPED), 1, SNAPPED)));
            return mock;
        }
    }

    @Autowired MockMvc mockMvc;

    @Test
    void 앵커가_도로_근처면_도로에_붙인_좌표를_돌려준다() throws Exception {
        mockMvc.perform(post("/api/route/overseas-anchor/validate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"country\":\"JP\",\"lat\":35.6812,\"lng\":139.7671}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ok").value(true))
                .andExpect(jsonPath("$.snapped.lat").value(35.681198))
                .andExpect(jsonPath("$.snapped.lng").value(139.767109));
    }

    @Test
    void 앵커가_도로에서_멀면_ok_false와_snapped_null이다() throws Exception {
        mockMvc.perform(post("/api/route/overseas-anchor/validate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"country\":\"JP\",\"lat\":35.0,\"lng\":140.5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ok").value(false))
                .andExpect(jsonPath("$.snapped").isEmpty());
    }

    @Test
    void 해외_걷기_응답은_앱이_읽는_필드를_모두_포함한다() throws Exception {
        mockMvc.perform(post("/api/route/overseas-walk")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"country":"JP","anchor":{"lat":35.68,"lng":139.76},
                                 "points":[{"lat":37.55,"lng":126.97},{"lat":37.56,"lng":126.97}],
                                 "state":null}"""))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ok").value(true))
                .andExpect(jsonPath("$.offRoad").value(false))
                .andExpect(jsonPath("$.matched[0].lat").value(35.681198))
                .andExpect(jsonPath("$.newAnchor.lng").value(139.767109))
                .andExpect(jsonPath("$.state.heading").value(10.0))
                .andExpect(jsonPath("$.state.krHeading").value(20.0))
                .andExpect(jsonPath("$.state.turnSide").value(1))
                .andExpect(jsonPath("$.state.trail[0].lat").value(35.681198))
                .andExpect(jsonPath("$.state.ideal.lng").value(139.767109));
    }

    @Test
    void 스냅에_실패하면_받은_좌표를_그대로_돌려준다() throws Exception {
        mockMvc.perform(post("/api/route/snap")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("[{\"lat\":37.5,\"lng\":127.0},{\"lat\":37.6,\"lng\":127.1}]"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[1].lat").value(37.6));
    }

    @Test
    void 토큰_없이_호출하면_401() throws Exception {
        mockMvc.perform(post("/api/route/overseas-walk")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void 좌표가_범위를_벗어나면_400() throws Exception {
        mockMvc.perform(post("/api/route/overseas-anchor/validate")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"country\":\"JP\",\"lat\":135.0,\"lng\":139.7671}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void anchor가_없는_걷기_요청은_400() throws Exception {
        mockMvc.perform(post("/api/route/overseas-walk")
                        .header("Authorization", "Bearer valid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"country\":\"JP\",\"points\":[]}"))
                .andExpect(status().isBadRequest());
    }
}
