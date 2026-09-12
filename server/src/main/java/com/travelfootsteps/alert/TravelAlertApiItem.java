package com.travelfootsteps.alert;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

// 외교부 여행경보 공공API의 원본 응답 한 건을 그대로 옮겨 담는 DTO.
// @JsonIgnoreProperties(ignoreUnknown = true): 공공API 응답에 여기 선언하지 않은 필드가
// 섞여 있어도(스펙 변경 등) 역직렬화가 실패하지 않고 무시하고 넘어간다.
// @JsonProperty로 공공API의 snake_case 필드명을 자바 camelCase 필드명에 매핑한다.
@JsonIgnoreProperties(ignoreUnknown = true)
public record TravelAlertApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("alarm_lvl") String alarmLevel,
        @JsonProperty("remark") String region,
        @JsonProperty("title") String title,
        @JsonProperty("wrt_dt") String issuedAt
) {
}
