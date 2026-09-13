package com.travelfootsteps.exchangerate;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

// 한국수출입은행 고시환율 API(exchangeJSON) 응답의 배열 원소 하나를 나타내는 레코드다.
// data.go.kr과 달리 이 API는 response/header/body 같은 "봉투" 구조 없이 배열을 최상위로
// 바로 반환한다 — 그래서 DataGoKrEnvelope 같은 감싸는 클래스가 필요 없다.
//
// @JsonIgnoreProperties(ignoreUnknown = true): 실제 응답에는 cur_nm(국가/통화명), ttb, tts,
// bkpr 등 이 태스크가 쓰지 않는 필드가 더 있다. 여기 선언하지 않은 필드는 무시하고, 필요한
// 세 필드만 골라서 매핑한다.
// @JsonProperty("...")로 API의 스네이크케이스 필드명을 자바 관례(카멜케이스) 이름에 매핑한다.
//
// result가 1이 아닌 항목(인증키 오류, DATA코드 오류, 일일 호출 한도 초과 등)은 cur_unit/deal_bas_r
// 없이 result만 채워질 수 있다 — 그런 항목은 호출부(ExchangeRateBatchScheduler)가
// result != 1 검사로 먼저 걸러내므로, normalizedCurrencyCode()/isPerHundredUnits()가
// null인 currencyUnit을 놓고 호출되는 일은 없다.
@JsonIgnoreProperties(ignoreUnknown = true)
public record KoreaEximApiItem(
        @JsonProperty("result") int result,
        @JsonProperty("cur_unit") String currencyUnit,
        @JsonProperty("deal_bas_r") String dealBaseRate
) {
    // 한국수출입은행 API는 100 단위로 고시되는 통화(JPY, IDR 등)를 cur_unit에 "JPY(100)"처럼
    // 표기한다. 괄호 앞부분만 잘라내면 우리가 저장/조회에 쓰는 3자리 통화코드가 된다.
    public String normalizedCurrencyCode() {
        int parenIndex = currencyUnit.indexOf('(');
        return parenIndex > 0 ? currencyUnit.substring(0, parenIndex) : currencyUnit;
    }

    // "(100)" 표기가 있으면 deal_bas_r이 "통화 100단위당 원화" 값이라는 뜻이다 — 배치가 이걸
    // 100으로 나눠서 "통화 1단위당 원화"로 정규화해야 한다(ExchangeRateBatchScheduler 참고).
    public boolean isPerHundredUnits() {
        return currencyUnit.contains("(100)");
    }
}
