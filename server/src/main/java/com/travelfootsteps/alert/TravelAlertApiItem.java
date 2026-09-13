package com.travelfootsteps.alert;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

// 외교부 여행경보 공공API의 원본 응답 한 건을 그대로 옮겨 담는 DTO.
// @JsonIgnoreProperties(ignoreUnknown = true): 공공API 응답에 여기 선언하지 않은 필드가
// 섞여 있어도(스펙 변경 등) 역직렬화가 실패하지 않고 무시하고 넘어간다.
// @JsonProperty로 공공API의 snake_case 필드명을 자바 camelCase 필드명에 매핑한다.
//
// 실제 API 응답(docs/api-samples/travel-alarm-vn.json)에는 title/headline에 해당하는 필드가
// 아예 없다 — TravelAlertResponse.title은 TravelAlertCollector가 국가명+등급으로 직접
// 조합해서 만든다 (이 DTO는 그 조합에 필요한 원본 필드만 담는다).
@JsonIgnoreProperties(ignoreUnknown = true)
public record TravelAlertApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("alarm_lvl") String alarmLevel,
        @JsonProperty("remark") String region,
        @JsonProperty("written_dt") String issuedAt
) {
}
