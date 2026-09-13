package com.travelfootsteps.embassy;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

// 외교부 재외공관 공공API의 원본 응답 한 건. lat/lng을 Double(래퍼 타입)로 받는 이유는
// 공공API가 좌표를 아예 비워서 내려주는 경우가 있어서다 — EmbassyCollector가 null 여부로
// 좌표 없는 항목을 걸러낼 수 있게 한다(원시 타입 double이면 null을 표현할 수 없다).
@JsonIgnoreProperties(ignoreUnknown = true)
public record EmbassyApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("embassy_ty_cd_nm") String type,
        @JsonProperty("embassy_kor_nm") String name,
        @JsonProperty("embassy_lat") Double lat,
        @JsonProperty("embassy_lng") Double lng,
        @JsonProperty("tel_no") String phone,
        @JsonProperty("urgency_tel_no") String emergencyPhone,
        @JsonProperty("emblgbd_addr") String address
) {
}
