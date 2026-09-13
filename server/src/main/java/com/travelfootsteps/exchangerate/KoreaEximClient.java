package com.travelfootsteps.exchangerate;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.travelfootsteps.externaldata.ExternalApiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.retry.backoff.BackOffContext;
import org.springframework.retry.backoff.BackOffPolicy;
import org.springframework.retry.policy.SimpleRetryPolicy;
import org.springframework.retry.support.RetryTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

/**
 * 한국수출입은행 고시환율 API(exchangeJSON) 전용 클라이언트.
 *
 * <p>Task 1의 {@code DataGoKrHttpClient}는 공공데이터포털 전용 봉투 구조를 파싱하므로 이
 * API(수출입은행)에는 그대로 재사용할 수 없다 — 제공 기관이 다르고 응답이 배열을 최상위로
 * 바로 반환하기 때문이다. 대신 "배치 재시도" 철학(전송 오류·파싱 오류를 1s/2s/4s 백오프로
 * 최대 3회 재시도, 최종 실패 시 {@link ExternalApiException}을 던져 호출부가 기존 캐시를
 * 그대로 유지할 수 있게 한다)은 Task 1과 동일하게 맞춘다.
 *
 * @Component: 스프링 빈으로 등록한다. 생성자에 필요한 RestClient.Builder(스프링 부트가
 * 자동 제공)와 application.yml의 korea-exim.api-key 값을 스프링이 주입해준다.
 */
@Component
public class KoreaEximClient {

    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final RestClient restClient;
    private final String apiKey;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public KoreaEximClient(RestClient.Builder builder, @Value("${korea-exim.api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://oapi.koreaexim.go.kr").build();
        this.apiKey = apiKey;
    }

    /** 오늘 날짜 기준 환율을 조회한다. 배치 스케줄러가 매일 호출하는 진입점이다. */
    public List<KoreaEximApiItem> fetchTodayRates() {
        return fetchRates(LocalDate.now());
    }

    /**
     * 지정한 날짜의 환율을 조회한다. 전송 오류(non-2xx, 타임아웃, 연결 실패)와 JSON 파싱 오류
     * 모두 {@link ExternalApiException}으로 감싸서 재시도 정책의 대상이 되게 한다.
     * 3회 재시도 후에도 실패하면 이 메서드가 {@link ExternalApiException}을 던진다 —
     * 호출부인 {@link ExchangeRateBatchScheduler}가 이를 잡아 로그만 남기고 기존 캐시를
     * 그대로 둔다.
     */
    public List<KoreaEximApiItem> fetchRates(LocalDate date) {
        RetryTemplate retryTemplate = buildRetryTemplate();
        return retryTemplate.execute(context -> fetchOnce(date));
    }

    private List<KoreaEximApiItem> fetchOnce(LocalDate date) {
        try {
            String body = restClient.get()
                    .uri(uriBuilder -> uriBuilder.path("/site/program/financial/exchangeJSON")
                            .queryParam("authkey", apiKey)
                            .queryParam("searchdate", date.format(DATE_FORMAT))
                            .queryParam("data", "AP01")
                            .build())
                    .retrieve()
                    .body(String.class);
            return List.of(objectMapper.readValue(body, KoreaEximApiItem[].class));
        } catch (ExternalApiException e) {
            throw e;
        } catch (Exception e) {
            // RestClient의 전송 오류(RestClientException 계열)와 Jackson의 파싱 오류를
            // 모두 여기서 ExternalApiException으로 통일한다 — 재시도 정책이 이 예외 타입만
            // 재시도하도록 설정돼 있기 때문이다.
            throw new ExternalApiException("한국수출입은행 환율 응답 처리 실패", e);
        }
    }

    /**
     * 재시도 템플릿을 구성한다. Task 1 DataGoKrHttpClient와 동일한 배치 재시도 정책:
     * 총 4회 시도(1회 초기 + 3회 재시도), ExternalApiException만 재시도 대상, 1s/2s/4s
     * 지수 백오프.
     */
    private RetryTemplate buildRetryTemplate() {
        RetryTemplate template = new RetryTemplate();
        template.setRetryPolicy(new SimpleRetryPolicy(4, Map.of(ExternalApiException.class, true)));
        template.setBackOffPolicy(new ExponentialBackOffPolicy());
        return template;
    }

    /** 1s → 2s → 4s 지수 백오프. 재시도 전 대기 시간은 2^(시도 횟수 - 1)초다. */
    private static class ExponentialBackOffPolicy implements BackOffPolicy {
        private int attempt = 0;

        @Override
        public void backOff(BackOffContext context) {
            attempt++;
            try {
                long backOffPeriod = 1000L * (1L << (attempt - 1));
                Thread.sleep(backOffPeriod);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        @Override
        public BackOffContext start(org.springframework.retry.RetryContext context) {
            attempt = 0;
            return new BackOffContext() {
            };
        }
    }
}
