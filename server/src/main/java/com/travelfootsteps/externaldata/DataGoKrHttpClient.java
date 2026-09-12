package com.travelfootsteps.externaldata;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.retry.RetryCallback;
import org.springframework.retry.backoff.FixedBackOffPolicy;
import org.springframework.retry.policy.SimpleRetryPolicy;
import org.springframework.retry.support.RetryTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 공공데이터포털(data.go.kr) 외교부 오픈API 공통 클라이언트.
 * 국가 단위 호출 실패 시 1회 초기 시도 후 1s/2s/4s 간격으로 최대 3회 재시도하고,
 * 그래도 실패하면 {@link ExternalApiException}을 던진다 — 호출부(수집기)가
 * 그 국가만 건너뛰고 배치를 계속 진행할 수 있게 한다.
 * HTTP 전송 오류(non-2xx, 연결 실패, 타임아웃 등)도 재시도 정책에 포함된다.
 *
 * @Component: 이 클래스를 스프링 빈으로 등록한다. 생성자에 RestClient.Builder와
 * DataGoKrProperties가 필요하면, 스프링이 자동으로 의존성을 주입한다.
 * RestClient.Builder는 스프링 부트 3.5부터 자동으로 제공되는 웹 클라이언트 빌더다.
 */
@Component
public class DataGoKrHttpClient {

    private final RestClient restClient;
    private final DataGoKrProperties properties;
    // ObjectMapper는 JSON을 파싱하고 객체로 변환하는 Jackson의 핵심 도구다.
    // 스프링이 자동으로 제공하는 ObjectMapper를 쓸 수도 있지만, 여기서는 새로 생성해도 된다.
    private final ObjectMapper objectMapper = new ObjectMapper();

    // 생성자 주입: 스프링 컨테이너가 RestClient.Builder를 주입해준다.
    // restClientBuilder가 null이 아니면 base URL을 설정해서 빌드하고,
    // null이면(테스트에서) 전달받은 restClient를 그대로 사용한다.
    public DataGoKrHttpClient(RestClient.Builder restClientBuilder, DataGoKrProperties properties) {
        this.restClient = restClientBuilder != null
                ? restClientBuilder.baseUrl("https://apis.data.go.kr").build()
                : null;
        this.properties = properties;
    }

    // 테스트에서 RestClient 인스턴스를 직접 주입하기 위한 생성자.
    // (프로덕션 코드에서는 위의 생성자만 쓰인다)
    DataGoKrHttpClient(RestClient restClient, DataGoKrProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    /**
     * 공공데이터포털 API를 호출해서 아이템 목록을 반환한다.
     *
     * @param path 상대 경로. 예: "/1360000/VilageFcstInfoService_2.0/getVilageFcst"
     * @param queryParams 쿼리 파라미터. 예: {"base_date": "20230915", "base_time": "0600"}
     * @param itemType 변환 대상 아이템 클래스. 예: VisaRequirement.class
     * @return 아이템 목록. 결과가 없으면 빈 리스트.
     * @throws ExternalApiException 응답 코드가 "00"이 아니거나, 파싱에 실패했거나,
     *         3회 재시도 후에도 실패한 경우.
     */
    public <T> List<T> getItems(String path, Map<String, String> queryParams, Class<T> itemType) {
        RetryTemplate retryTemplate = buildRetryTemplate();
        // RetryCallback은 재시도될 수 있는 작업을 나타낸다. 각 재시도마다 fetchOnce()를 호출한다.
        RetryCallback<List<T>, ExternalApiException> callback = context -> fetchOnce(path, queryParams, itemType);
        return retryTemplate.execute(callback);
    }

    /**
     * 재시도 없이 한 번 호출한다. RetryTemplate에 의해 재시도될 수 있다.
     * 공공데이터포털 응답을 파싱하고, resultCode가 "00"이 아니면 예외를 던진다.
     * HTTP 전송 오류(non-2xx, 타임아웃 등)도 ExternalApiException으로 감싸서
     * 재시도 정책과 통일된 예외 처리를 보장한다.
     */
    private <T> List<T> fetchOnce(String path, Map<String, String> queryParams, Class<T> itemType) {
        // 쿼리 파라미터에 serviceKey와 returnType을 자동으로 추가한다.
        // LinkedHashMap을 쓰면 파라미터 순서가 유지되어 테스트나 디버깅이 쉬워진다.
        Map<String, String> allParams = new LinkedHashMap<>(queryParams);
        allParams.putIfAbsent("serviceKey", properties.serviceKey());
        allParams.putIfAbsent("returnType", "JSON");

        try {
            // RestClient를 쓰면 Spring의 선호 HTTP 클라이언트인 RestTemplate보다 간결한 코드를 쓸 수 있다.
            // uri(uriBuilder -> ...)로 경로와 쿼리 파라미터를 설정한다.
            // HTTP 전송 오류(non-2xx, 연결 실패, 타임아웃 등)도 여기서 발생하며,
            // 아래 catch 블록에서 ExternalApiException으로 감싸진다.
            String responseBody = restClient.get()
                    .uri(uriBuilder -> {
                        var builder = uriBuilder.path(path);
                        allParams.forEach(builder::queryParam);
                        return builder.build();
                    })
                    .retrieve()
                    .body(String.class);

            // JSON 응답을 DataGoKrEnvelope로 파싱한다.
            DataGoKrEnvelope envelope = objectMapper.readValue(responseBody, DataGoKrEnvelope.class);
            // resultCode가 "00"이 아니면 에러 응답이다. 예외를 던진다.
            if (envelope.response() == null || envelope.response().header() == null
                    || !"00".equals(envelope.response().header().resultCode())) {
                String msg = envelope.response() != null && envelope.response().header() != null
                        ? envelope.response().header().resultMsg() : "unknown";
                throw new ExternalApiException("공공데이터포털 응답 오류: " + msg);
            }
            // resultCode가 "00"이면 성공. 아이템을 추출해서 반환한다.
            return extractItems(envelope, itemType);
        } catch (ExternalApiException e) {
            // ExternalApiException이면 그대로 던진다. (이미 정의된 예외)
            throw e;
        } catch (Exception e) {
            // 그 외 모든 예외(JSON 파싱 실패, HTTP 오류, 연결 실패 등)를 ExternalApiException으로 감싼다.
            // 재시도 정책이 이 예외 타입만 재시도하도록 설정되어 있다.
            throw new ExternalApiException("공공데이터포털 호출 실패", e);
        }
    }

    /**
     * DataGoKrEnvelope에서 아이템을 추출해서 목록으로 반환한다.
     * item이 null, 빈 문자열, 객체, 배열 중 어느 것이든 처리할 수 있다.
     */
    private <T> List<T> extractItems(DataGoKrEnvelope envelope, Class<T> itemType) throws Exception {
        if (envelope.response().body() == null || envelope.response().body().items() == null) {
            return List.of();
        }
        var itemNode = envelope.response().body().items().item();
        // item이 null이거나, JSON 노드에서 null이거나, 빈 문자열이면 빈 리스트를 반환한다.
        if (itemNode == null || itemNode.isNull() || (itemNode.isTextual() && itemNode.asText().isEmpty())) {
            return List.of();
        }
        // item이 배열이면 여러 개의 아이템이 있다. 배열을 itemType의 리스트로 변환한다.
        if (itemNode.isArray()) {
            return objectMapper.readerForListOf(itemType).readValue(itemNode);
        }
        // item이 단일 객체면 리스트에 담아서 반환한다.
        return List.of(objectMapper.treeToValue(itemNode, itemType));
    }

    /**
     * 재시도 템플릿을 구성한다.
     * SimpleRetryPolicy: 총 4회 시도(1회 초기 + 3회 재시도), ExternalApiException만 재시도한다.
     * ExponentialBackOffPolicy: 1회 초기 시도 후, 재시도 전에 1초/2초/4초 대기.
     */
    private RetryTemplate buildRetryTemplate() {
        RetryTemplate template = new RetryTemplate();
        // 총 4회 시도(1회 초기 + 3회 재시도)를 허용하고, ExternalApiException만 재시도 가능으로 설정한다.
        // 다른 예외(e.g., NullPointerException)가 발생하면 재시도하지 않고 즉시 던진다.
        SimpleRetryPolicy retryPolicy = new SimpleRetryPolicy(4, Map.of(ExternalApiException.class, true));
        template.setRetryPolicy(retryPolicy);

        // 백오프 정책: 1s → 2s → 4s (재시도 전 대기)
        org.springframework.retry.backoff.BackOffPolicy backOffPolicy = new ExponentialBackOffPolicy();
        template.setBackOffPolicy(backOffPolicy);
        return template;
    }

    /**
     * 1s → 2s → 4s 지수 백오프를 구현한다.
     * 이름을 명확히 하기 위해 BackOffPolicy 인터페이스를 직접 구현했다.
     * 백오프 간격은 2^(attempt-1) 초다.
     */
    private static class ExponentialBackOffPolicy implements org.springframework.retry.backoff.BackOffPolicy {
        private int attempt = 0;

        @Override
        public void backOff(org.springframework.retry.backoff.BackOffContext context) {
            attempt++;
            try {
                // attempt=1일 때 1s(1000ms), attempt=2일 때 2s(2000ms), attempt=3일 때 4s(4000ms)
                long backOffPeriod = 1000L * (1L << (attempt - 1));
                Thread.sleep(backOffPeriod);
            } catch (InterruptedException e) {
                // InterruptedException이 발생하면 그냥 무시한다. (복구 불가능)
                Thread.currentThread().interrupt();
            }
        }

        @Override
        public org.springframework.retry.backoff.BackOffContext start(org.springframework.retry.RetryContext context) {
            // 각 새로운 시도마다 attempt을 초기화한다.
            attempt = 0;
            return new org.springframework.retry.backoff.BackOffContext() {
            };
        }
    }
}
