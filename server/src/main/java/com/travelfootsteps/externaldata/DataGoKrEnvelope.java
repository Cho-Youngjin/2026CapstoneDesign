package com.travelfootsteps.externaldata;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.JsonNode;

// 공공데이터포털의 공통 JSON 응답 구조를 나타내는 "봉투" 클래스다.
// 모든 data.go.kr API 응답은 response > header > resultCode 구조를 가지고 있다.
// 실제 데이터는 response > body > items > item 아래에 있다.
//
// @JsonIgnoreProperties(ignoreUnknown = true)는 JSON에 있지만 이 클래스에는 정의되지 않은
// 필드들을 무시하라는 뜻이다. API 응답이 변경되어 새 필드가 추가돼도 파싱이 깨지지 않는다.
//
// item을 JsonNode로 받는 이유는 공공데이터포털의 비일관성을 흡수하기 위해서다:
// - 결과가 0건일 때: item이 빈 문자열 ""
// - 결과가 1건일 때: item이 JSON 객체 {...}
// - 결과가 여러 건일 때: item이 JSON 배열 [{...}, {...}]
// JsonNode로 받으면 위의 세 경우를 모두 처리할 수 있다. 실제 타입 변환은
// DataGoKrHttpClient.extractItems()에서 처리한다.
@JsonIgnoreProperties(ignoreUnknown = true)
public record DataGoKrEnvelope(Response response) {

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Response(Header header, Body body) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Header(String resultCode, String resultMsg) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Body(Items items) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Items(JsonNode item) {
    }
}
