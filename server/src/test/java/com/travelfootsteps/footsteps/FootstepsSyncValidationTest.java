package com.travelfootsteps.footsteps;

import com.travelfootsteps.country.CountryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * FootstepsSyncController의 요청 검증(@Valid List&lt;...&gt;)만 확인하는 슬라이스 테스트.
 *
 * <p>{@link FootstepsSyncControllerTest}(전체 {@code @SpringBootTest} + Testcontainers)와
 * 달리 이 클래스는 DB/도커 없이도 실행된다 — {@code @WebMvcTest}로 컨트롤러 계층만 띄우고
 * 리포지토리는 {@code @MockitoBean}으로, 보안 필터는 {@code addFilters = false}로 꺼서 순수하게
 * "요청 본문 리스트의 각 원소가 검증되는가"만 확인한다.
 *
 * <p>이 테스트가 존재하는 이유: {@code @Valid @RequestBody List<Foo> items}처럼 파라미터 타입이
 * 바로 List인 경우, Bean Validation이 리스트의 각 원소까지 캐스케이딩 검증하는지는 프레임워크
 * 버전에 따라 다르다고 알려져 있어(흔한 함정 — 위 방식이 전혀 검증하지 않고 그대로 통과시키는
 * 스프링 버전도 있다), 실제로 이 프로젝트의 스프링 부트 버전에서 동작하는지 직접 확인해야 한다.
 */
@WebMvcTest(controllers = FootstepsSyncController.class)
@AutoConfigureMockMvc(addFilters = false)
class FootstepsSyncValidationTest {

    @Autowired
    MockMvc mockMvc;

    @MockitoBean
    CountryRepository countryRepository;
    @MockitoBean
    CheckinRepository checkinRepository;
    @MockitoBean
    DailyStepRepository dailyStepRepository;

    @Test
    void 체크인_배치의_한_항목이라도_countryIso가_비어있으면_400() throws Exception {
        mockMvc.perform(post("/api/checkins")
                        .contentType("application/json")
                        .content("""
                                [
                                  {"localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
                                   "recordedAt": "2026-12-20T09:00:00Z", "source": "AUTO"},
                                  {"localId": 2, "lat": 10.8, "lng": 106.6, "countryIso": "",
                                   "recordedAt": "2026-12-20T09:00:00Z", "source": "AUTO"}
                                ]
                                """))
                .andExpect(status().isBadRequest());
    }

    @Test
    void 체크인의_source가_허용된_값이_아니면_400() throws Exception {
        mockMvc.perform(post("/api/checkins")
                        .contentType("application/json")
                        .content("""
                                [
                                  {"localId": 1, "lat": 10.8, "lng": 106.6, "countryIso": "VN",
                                   "recordedAt": "2026-12-20T09:00:00Z", "source": "BOGUS"}
                                ]
                                """))
                .andExpect(status().isBadRequest());
    }

    @Test
    void 걸음수_배치의_한_항목이라도_stepCount가_음수이면_400() throws Exception {
        mockMvc.perform(post("/api/daily-steps")
                        .contentType("application/json")
                        .content("""
                                [
                                  {"localId": 1, "date": "2026-12-20", "countryIso": "VN", "stepCount": 100},
                                  {"localId": 2, "date": "2026-12-21", "countryIso": "VN", "stepCount": -1}
                                ]
                                """))
                .andExpect(status().isBadRequest());
    }
}
