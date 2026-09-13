package com.travelfootsteps.translate;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

// TranslationClient 인터페이스의 "진짜" 구현체. Google Cloud Translation v2 REST API를
// 호출해서 실제로 번역한다.
// @Component: 스프링에게 이 클래스를 빈으로 등록해달라고 알린다.
// @Profile("!test")는 auth 패키지의 FirebaseTokenVerifier와 같은 이유다 — 테스트 프로필에서는
// 이 빈이 아예 생기지 않고, 그 자리는 테스트 코드가 등록하는 Mockito 목(mock)이 대신 채운다.
// 그래야 컨트롤러 테스트가 실제 Google 서버에 네트워크로 요청을 보내지 않는다.
@Component
@Profile("!test")
public class GoogleTranslateClient implements TranslationClient {

    private final RestClient restClient;
    private final String apiKey;

    // @Value("${google.server-api-key}")는 application.yml의 google.server-api-key 값을
    // (그리고 그 값은 다시 server/.env의 GOOGLE_SERVER_API_KEY를 읽어 채워진다) 이 생성자
    // 파라미터로 주입한다. 키를 코드에 직접 적지 않고 설정으로 분리해두면, 저장소에 키가
    // 커밋되는 사고를 막을 수 있다(.env는 .gitignore 대상). 이 값은 로그에도 절대 남기지 않는다.
    public GoogleTranslateClient(RestClient.Builder builder, @Value("${google.server-api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://translation.googleapis.com").build();
        this.apiKey = apiKey;
    }

    // 이 메서드의 재시도 정책은 externaldata.DataGoKrHttpClient(공공데이터 배치 수집)의
    // 정책과 "의도적으로" 다르다. 배치는 하루 한 번 조용히 도는 백그라운드 작업이라, 국가 하나가
    // 실패해도 1s/2s/4s로 기다려가며 최대 3회 더 재시도할 여유가 있다(그동안 아무도 기다리지 않는다).
    // 반면 이 메서드는 앱 사용자가 화면 앞에서 응답을 기다리는 "사용자 요청 경로"다. 여기서
    // 지수 백오프로 몇 초씩 대기하면 사용자 체감 지연이 그대로 늘어난다. 그래서 Global Constraints가
    // 정한 대로: 실패하면 대기 없이 즉시 1회만 다시 시도하고, 그마저 실패하면 더 기다리게 하지 않고
    // 바로 502 Bad Gateway로 앱에 알린다 — 앱이 "지금은 번역이 안 된다"고 빠르게 사용자에게
    // 보여줄 수 있게 하기 위함이다.
    // catch 대상을 Exception이 아니라 RestClientException(RestClient가 던지는 모든 통신 실패의
    // 공통 상위 타입 — 4xx/5xx 응답, 연결 실패, 타임아웃 등)으로 좁혀둔 이유: Exception을 그대로
    // 잡으면 우리 코드의 진짜 버그(예: 응답 JSON 구조가 예상과 달라 callOnce()에서 NullPointerException이
    // 나는 경우)까지 "그냥 통신이 잠깐 실패했나 보다"며 502로 뭉개버린다. 그러면 실제로는 코드를
    // 고쳐야 하는 문제가 마치 정상적인 외부 서비스 장애처럼 보여서 원인을 찾기 어려워진다.
    // RestClientException만 잡으면, 프로그래밍 버그는 그대로 500(미처리 예외)으로 드러나고
    // 진짜 네트워크/HTTP 실패만 이 재시도-후-502 정책의 대상이 된다.
    @Override
    public TranslationResult translate(String text, String targetLanguage, String sourceLanguage) {
        try {
            return callOnce(text, targetLanguage, sourceLanguage);
        } catch (RestClientException firstFailure) {
            try {
                return callOnce(text, targetLanguage, sourceLanguage);
            } catch (RestClientException secondFailure) {
                // ResponseStatusException: 스프링이 알아서 이 예외를 지정한 HTTP 상태 코드
                // 응답으로 바꿔준다. 컨트롤러 어드바이스를 따로 만들 필요가 없다.
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "번역 서비스 호출 실패", secondFailure);
            }
        }
    }

    private TranslationResult callOnce(String text, String targetLanguage, String sourceLanguage) {
        Map<String, Object> body = sourceLanguage == null
                ? Map.of("q", text, "target", targetLanguage, "format", "text")
                : Map.of("q", text, "target", targetLanguage, "source", sourceLanguage, "format", "text");

        // RestClient: 스프링 부트 3.2+가 제공하는 동기 HTTP 클라이언트. RestTemplate보다
        // 유창한(fluent) API로 요청을 구성할 수 있다. .body(body)는 body를 JSON으로 직렬화해
        // 요청 바디에 싣는다(Jackson이 classpath에 있으면 자동으로 JSON 변환기를 고른다).
        JsonNode response = restClient.post()
                .uri(uriBuilder -> uriBuilder.path("/language/translate/v2").queryParam("key", apiKey).build())
                .body(body)
                .retrieve()
                .body(JsonNode.class);

        JsonNode translation = response.path("data").path("translations").get(0);
        String translatedText = translation.path("translatedText").asText();
        String detected = sourceLanguage == null && translation.hasNonNull("detectedSourceLanguage")
                ? translation.path("detectedSourceLanguage").asText() : null;

        return new TranslationResult(translatedText, detected);
    }
}
