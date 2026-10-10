package com.travelfootsteps.exchangerate;

import java.math.BigDecimal;
import java.time.LocalDate;

// 조회 API(GET /api/exchange-rates/{currencyCode})의 응답 바디. 컨트롤러가 이 레코드를 반환하면
// 스프링(Jackson)이 필드 이름 그대로 JSON으로 직렬화한다.
// 앞의 세 필드 {currencyCode, krwRate, baseDate}는 Plan B와의 기존 계약이라 그대로 두고, 지갑·환율 알림
// 설계 §4.5의 네 필드를 뒤에 덧붙였다 — 필드를 "추가"만 했으므로 기존 클라이언트는 깨지지 않는다.
// - previousKrwRate/previousBaseDate: 직전 고시일 값. 아직 하루치만 받았으면 null.
// - changePercent: 전 영업일 대비 등락률(%), 소수 둘째 자리. 이전값이 없으면 null.
// - source: "EXIM"(한국수출입은행) 또는 "ER_API"(참고환율). 앱이 출처 표기를 고르는 데 쓴다.
public record ExchangeRateResponse(
        String currencyCode,
        BigDecimal krwRate,
        LocalDate baseDate,
        BigDecimal previousKrwRate,
        LocalDate previousBaseDate,
        BigDecimal changePercent,
        String source
) {
    public static ExchangeRateResponse from(ExchangeRate rate) {
        return new ExchangeRateResponse(
                rate.getCurrencyCode().trim(), // CHAR(3) 컬럼이라 공백이 붙어 올 수 있다
                rate.getKrwRate(),
                rate.getBaseDate(),
                rate.getPreviousKrwRate(),
                rate.getPreviousBaseDate(),
                rate.changePercent(),
                rate.getSource().name());
    }
}
