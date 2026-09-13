package com.travelfootsteps.exchangerate;

import java.math.BigDecimal;
import java.time.LocalDate;

// 조회 API(GET /api/exchange-rates/{currencyCode})의 응답 바디. Plan B와의 계약(binding
// contract)이므로 필드 이름/타입을 임의로 바꾸면 안 된다: {currencyCode, krwRate, baseDate}.
public record ExchangeRateResponse(String currencyCode, BigDecimal krwRate, LocalDate baseDate) {
    public static ExchangeRateResponse from(ExchangeRate rate) {
        return new ExchangeRateResponse(rate.getCurrencyCode(), rate.getKrwRate(), rate.getBaseDate());
    }
}
