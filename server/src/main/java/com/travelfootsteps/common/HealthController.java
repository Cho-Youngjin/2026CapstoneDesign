package com.travelfootsteps.common;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

// @RestController = @Controller + @ResponseBody. 이 클래스의 메서드가 리턴하는 값(Map 등)을
// 화면(HTML)이 아니라 JSON으로 직접 응답 본문에 써준다는 뜻이다.
// @RequestMapping("/api")는 이 컨트롤러의 모든 엔드포인트 앞에 공통으로 "/api"를 붙인다.
@RestController
@RequestMapping("/api")
public class HealthController {

    // 이 서버가 살아있는지 확인하는 헬스체크 엔드포인트.
    // SecurityConfig에서 인증 없이(permitAll) 열어두었기 때문에, 토큰 없이 GET /api/health로
    // 호출해도 항상 200과 {"status":"UP"}을 받는다 — 배포/모니터링에서 "서버가 떠 있나?"만 확인할 때 쓴다.
    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
