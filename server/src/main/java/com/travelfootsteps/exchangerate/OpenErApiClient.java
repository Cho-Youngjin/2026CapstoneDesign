package com.travelfootsteps.exchangerate;

import com.travelfootsteps.externaldata.ExternalApiException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * open.er-api.com 무료(Open Access) 환율 API 클라이언트. 한국수출입은행이 고시하지 않는 통화
 * (VND, TWD, PHP, TRY, CZK, CNY)의 참고환율을 받아오는 데만 쓴다(지갑·환율 알림 설계 §4.4).
 *
 * <p>API 키가 필요 없고, 값은 하루 한 번 갱신된다. 과도하게 호출하면 HTTP 429가 오므로 배치가
 * 하루 몇 번만 부른다. 이용 조건상 화면에 출처 표기("Rates By Exchange Rate API")가 필요하다 —
 * 그래서 이 값으로 채운 행은 source=ER_API로 저장해 앱이 출처를 구분할 수 있게 한다.
 *
 * <p>@Component: 스프링 빈으로 등록한다. 생성자의 RestClient.Builder는 스프링 부트가 자동으로
 * 만들어 주입한다(KoreaEximClient·GooglePlacesClient와 같은 방식).
 *
 * <p>재시도는 하지 않는다. 배치가 하루 세 번 돌기 때문에 한 번 실패해도 다음 실행에서 다시 받는다.
 * 실패는 {@link ExternalApiException}으로 통일해 던지고, 호출부(배치)가 잡아 기존 캐시를 유지한다.
 */
@Component
public class OpenErApiClient {

    private final RestClient restClient;

    public OpenErApiClient(RestClient.Builder builder) {
        this.restClient = builder.baseUrl("https://open.er-api.com").build();
    }

    public OpenErApiResponse fetchKrwBase() {
        OpenErApiResponse body;
        try {
            body = restClient.get()
                    .uri("/v6/latest/KRW")
                    .retrieve()
                    .body(OpenErApiResponse.class);
        } catch (RestClientException e) {
            // 4xx/5xx 응답, 연결 실패, 타임아웃, JSON 변환 실패가 모두 RestClientException 계열이다.
            throw new ExternalApiException("open.er-api.com 호출 실패", e);
        }
        if (body == null || !"success".equals(body.result()) || body.rates() == null) {
            throw new ExternalApiException("open.er-api.com 응답이 성공이 아님: "
                    + (body == null ? "본문 없음" : body.result()));
        }
        return body;
    }
}
