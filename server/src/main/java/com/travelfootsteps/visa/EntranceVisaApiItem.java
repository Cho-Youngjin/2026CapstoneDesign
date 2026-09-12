package com.travelfootsteps.visa;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

// 외교부 입국허가요건(EntranceVisaService2) API 응답의 item 하나를 그대로 옮겨 담는 레코드다.
// Jackson(스프링 부트가 기본으로 쓰는 JSON 파서)은 기본적으로 JSON 필드명과 자바 필드명이
// 스네이크→카멜(예: country_nm -> countryNm)로 자동 변환되길 기대하지만, 이 API 응답 필드명은
// country_iso_alp2, gnrl_pspt_visa_yn처럼 스네이크·약어가 뒤섞여 있어 자동 변환 규칙과 안 맞는다.
// 그래서 필드마다 @JsonProperty로 실제 JSON 키를 명시적으로 지정한다.
//
// record: 자바 14+ 문법으로, 불변 데이터를 담는 값 객체다. 생성자·getter·equals·hashCode·toString이
// 자동으로 생긴다 — DTO(외부 데이터 전달 객체)처럼 "그냥 값을 담아 나르기만 하는" 용도에 딱 맞는다.
// 이 레코드는 DB 엔티티(VisaRequirement)가 아니라 API 응답 매핑 전용이라는 점에 유의한다.
//
// @JsonIgnoreProperties(ignoreUnknown = true): 이 레코드에 정의하지 않은 JSON 필드가 응답에
// 더 있어도 무시하고 넘어간다. 외교부 API가 나중에 필드를 추가해도 파싱이 깨지지 않게 해준다.
@JsonIgnoreProperties(ignoreUnknown = true)
public record EntranceVisaApiItem(
        @JsonProperty("country_iso_alp2") String countryIsoAlp2,
        @JsonProperty("country_nm") String countryNm,
        @JsonProperty("gnrl_pspt_visa_yn") String gnrlPsptVisaYn,
        @JsonProperty("gnrl_pspt_visa_cn") String gnrlPsptVisaCn,
        @JsonProperty("nvisa_entry_evdc_cn") String nvisaEntryEvdcCn,
        @JsonProperty("remark") String remark
) {
}
