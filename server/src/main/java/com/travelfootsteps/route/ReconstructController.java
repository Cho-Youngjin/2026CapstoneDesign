package com.travelfootsteps.route;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// 경로 복원 API(설계 2026-11-07 6장). 앱의 날짜별 보기(R7)와 R6 분석이 하루치 드문 점·머문 곳을 보내 복원 경로를 받는다.
// 기록 좌표는 저장하지 않고 응답만 만든다(설계 9-3).
//
// @RestController: 이 클래스가 HTTP 요청을 받는 컨트롤러이고, 메서드가 돌려준 객체를 JSON으로 바꿔 응답한다는 뜻이다.
// @RequestMapping("/api/route"): 이 클래스 메서드들의 공통 경로 앞부분이다. RouteController도 같은 앞부분을 쓰지만,
// 스프링은 전체 경로(+ HTTP 메서드)가 겹치지만 않으면 여러 컨트롤러에 나눠 둘 수 있다.
// 인증은 SecurityConfig의 "/api/**는 로그인 필요" 규칙이 컨트롤러보다 먼저 도는 필터에서 처리하므로 여기서는 모른다.
// @RequiredArgsConstructor(Lombok): final 필드를 받는 생성자를 만들어, 스프링이 그 생성자로 서비스 빈을 넣어 준다.
@RestController
@RequestMapping("/api/route")
@RequiredArgsConstructor
public class ReconstructController {

    private final RouteReconstructionService reconstructionService;

    // @RequestBody: 요청 본문 JSON을 ReconstructRequest로 바꾼다. @Valid: 바꾼 직후 그 안의 검증 규칙(점 2000개 상한,
    // 좌표 범위 등)을 검사해, 어기면 이 메서드를 부르지 않고 400 Bad Request로 끝낸다.
    @PostMapping("/reconstruct")
    public ReconstructResponse reconstruct(@RequestBody @Valid ReconstructRequest request) {
        return reconstructionService.reconstruct(request);
    }
}
