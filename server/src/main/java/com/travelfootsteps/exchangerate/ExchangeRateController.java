package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

// @RestController + @RequestMapping("/api/exchange-rates"): 이 클래스의 메서드들이 HTTP
// 요청을 처리하고 반환값을 JSON으로 직렬화해 응답 바디에 담는다. 다른 /api/**와 달리 이 GET 조회는
// SecurityConfig에서 permitAll로 열려 있어 토큰 없이도 호출된다 — 앱의 백그라운드 알림 작업에는
// 로그인 토큰이 없기 때문이다(지갑·환율 알림 설계 §4.5). 토큰을 붙여 호출해도 똑같이 동작한다.
// @RequiredArgsConstructor(Lombok): final 필드(repository)를 받는 생성자를 자동 생성한다.
//
// 이 컨트롤러는 배치가 미리 채워둔 캐시를 읽기만 한다 — 외부 API를 직접 호출하지 않으므로
// 재시도 로직이 필요 없다(Global Constraints: "단순 사용자용 DB 읽기").
@RestController
@RequestMapping("/api/exchange-rates")
@RequiredArgsConstructor
public class ExchangeRateController {

    private final ExchangeRateRepository repository;

    @GetMapping("/{currencyCode}")
    public ExchangeRateResponse get(@PathVariable String currencyCode) {
        return repository.findByCurrencyCode(currencyCode.toUpperCase())
                .map(ExchangeRateResponse::from)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "캐시된 환율이 없습니다: " + currencyCode));
    }
}
