package com.travelfootsteps.externaldata;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * DataGoKrHttpClient의 단위 테스트.
 * 스프링 컨텍스트 없이 RestClient의 목 인터셉터를 쓰므로 빠르다.
 */
class DataGoKrHttpClientTest {

    // 테스트용 더미 아이템 클래스.
    record DummyItem(String countryNm) {
    }

    /**
     * resultCode가 "00"이면 item 목록을 반환한다.
     */
    @Test
    void resultCode_00이면_item_목록을_반환한다() {
        // 공공데이터포털 응답 JSON. resultCode가 "00"이고, item이 배열로 1개의 객체를 포함한다.
        String body = """
                {"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE"},
                "body":{"items":{"item":[{"countryNm":"베트남"}]}}}}
                """;
        // RestClient를 목 인터셉터로 감싸서, 실제 HTTP 요청 대신 고정된 응답을 반환하게 한다.
        // UTF-8로 명시적으로 인코딩한다.
        RestClient restClient = RestClient.builder()
                .requestInterceptor((request, requestBody, execution) -> {
                    var response = new org.springframework.mock.http.client.MockClientHttpResponse(
                            body.getBytes(StandardCharsets.UTF_8), org.springframework.http.HttpStatus.OK);
                    response.getHeaders().setContentType(
                            new org.springframework.http.MediaType(org.springframework.http.MediaType.APPLICATION_JSON, StandardCharsets.UTF_8));
                    return response;
                })
                .build();
        DataGoKrHttpClient client = new DataGoKrHttpClient(restClient, new DataGoKrProperties("key"));

        // 클라이언트를 호출한다.
        List<DummyItem> items = client.getItems("/test", Map.of(), DummyItem.class);

        // resultCode가 "00"이므로 item이 반환되어야 한다.
        assertThat(items).hasSize(1);
        assertThat(items.get(0).countryNm()).isEqualTo("베트남");
    }

    /**
     * resultCode가 "00"이 아니면 3회 재시도 후 예외를 던진다.
     * 이 테스트는 백오프 때문에 약 7초(1s+2s+4s) 소요된다.
     */
    @Test
    void resultCode가_00이_아니면_3회_재시도_후_예외를_던진다() {
        // 호출 횟수를 세기 위한 카운터.
        AtomicInteger attempts = new AtomicInteger();
        // 공공데이터포털 에러 응답. resultCode가 "99"다.
        String errorBody = """
                {"response":{"header":{"resultCode":"99","resultMsg":"UNKNOWN ERROR"},"body":{"items":{"item":""}}}}
                """;
        // 매 요청마다 시도 횟수를 증가시키고, 항상 같은 에러 응답을 반환한다.
        RestClient restClient = RestClient.builder()
                .requestInterceptor((request, requestBody, execution) -> {
                    attempts.incrementAndGet();
                    var response = new org.springframework.mock.http.client.MockClientHttpResponse(
                            errorBody.getBytes(StandardCharsets.UTF_8), org.springframework.http.HttpStatus.OK);
                    response.getHeaders().setContentType(
                            new org.springframework.http.MediaType(org.springframework.http.MediaType.APPLICATION_JSON, StandardCharsets.UTF_8));
                    return response;
                })
                .build();
        DataGoKrHttpClient client = new DataGoKrHttpClient(restClient, new DataGoKrProperties("key"));

        // 클라이언트를 호출한다. resultCode가 "00"이 아니므로 ExternalApiException을 던져야 한다.
        assertThatThrownBy(() -> client.getItems("/test", Map.of(), DummyItem.class))
                .isInstanceOf(ExternalApiException.class);
        // resultCode가 "00"이 아니므로, 첫 시도 + 3회 재시도 = 총 4회 시도해야 한다.
        // (초기: 실패 → 재시도 1: 실패(1s 대기 후) → 재시도 2: 실패(2s 대기 후) → 재시도 3: 실패(4s 대기 후) → 예외)
        assertThat(attempts.get()).isEqualTo(4);
    }

    /**
     * HTTP 전송 실패(non-2xx 응답, 연결 오류 등)도 ExternalApiException으로 감싸져서
     * 같은 재시도 정책을 따른다.
     * 이 테스트는 백오프 때문에 약 7초(1s+2s+4s) 소요된다.
     */
    @Test
    void HTTP_전송_실패도_3회_재시도_후_예외를_던진다() {
        // 호출 횟수를 세기 위한 카운터.
        AtomicInteger attempts = new AtomicInteger();
        // 매 요청마다 시도 횟수를 증가시키고, HTTP 500 오류를 반환한다.
        RestClient restClient = RestClient.builder()
                .requestInterceptor((request, requestBody, execution) -> {
                    attempts.incrementAndGet();
                    // HTTP 500 응답을 반환하면, RestClient.retrieve()가 RestClientResponseException을 던진다.
                    var response = new org.springframework.mock.http.client.MockClientHttpResponse(
                            "{}".getBytes(StandardCharsets.UTF_8), HttpStatus.INTERNAL_SERVER_ERROR);
                    return response;
                })
                .build();
        DataGoKrHttpClient client = new DataGoKrHttpClient(restClient, new DataGoKrProperties("key"));

        // HTTP 500 오류가 ExternalApiException으로 감싸져서 던져져야 한다.
        assertThatThrownBy(() -> client.getItems("/test", Map.of(), DummyItem.class))
                .isInstanceOf(ExternalApiException.class)
                .hasMessageContaining("호출 실패");
        // HTTP 전송 오류도 재시도 정책에 포함되므로, 총 4회 시도해야 한다.
        assertThat(attempts.get()).isEqualTo(4);
    }
}
