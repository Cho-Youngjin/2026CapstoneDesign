package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

// @RestController + @RequestMapping("/api/exchange-rates"): 이 클래스의 메서드들이 HTTP
// 요청을 처리하고 반환값을 JSON으로 직렬화해 응답 바디에 담는다. SecurityConfig의
// "/api/**".authenticated() 규칙에 걸리므로, 이 엔드포인트도 다른 /api/** 와 마찬가지로
// Authorization 헤더의 Firebase ID 토큰이 있어야 접근할 수 있다.
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
