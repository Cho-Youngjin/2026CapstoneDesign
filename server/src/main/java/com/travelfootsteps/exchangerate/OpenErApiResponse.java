package com.travelfootsteps.exchangerate;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;
import java.util.Map;

// open.er-api.com/v6/latest/KRW 응답에서 이 서버가 쓰는 세 필드만 매핑한 레코드다.
// - result: 성공이면 "success". 실패하면 "error"와 함께 error-type이 온다.
// - time_last_update_unix: 이 환율이 갱신된 시각(UTC 유닉스 초). 배치가 이걸 KST 날짜로 바꿔 baseDate로 쓴다.
// - rates: KRW 기준이라 "1원 = 몇 단위"다(예: VND 19.255146). 원화 환율은 배치가 1 / rates[code]로 뒤집는다.
// @JsonIgnoreProperties(ignoreUnknown = true): provider, terms_of_use 등 쓰지 않는 필드는 무시한다.
// @JsonProperty: API의 스네이크케이스 필드명을 자바 관례 이름에 연결한다.
@JsonIgnoreProperties(ignoreUnknown = true)
public record OpenErApiResponse(
        @JsonProperty("result") String result,
        @JsonProperty("time_last_update_unix") long timeLastUpdateUnix,
        @JsonProperty("rates") Map<String, BigDecimal> rates
) {
}
