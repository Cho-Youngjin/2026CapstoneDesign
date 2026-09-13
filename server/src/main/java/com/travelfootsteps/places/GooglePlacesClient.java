package com.travelfootsteps.places;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;

// PlacesClient 인터페이스의 "진짜" 구현체. Google Places API(Nearby Search)를 호출한다.
// @Component + @Profile("!test")는 GoogleTranslateClient와 같은 이유다 — 테스트 프로필에서는
// 이 빈이 생기지 않고, 테스트 코드가 등록한 Mockito 목이 대신 PlacesClient 자리를 채운다.
@Component
@Profile("!test")
public class GooglePlacesClient implements PlacesClient {

    private final RestClient restClient;
    private final String apiKey;

    // GoogleTranslateClient와 동일하게, API 키는 코드에 적지 않고 application.yml
    // (google.server-api-key, 실제 값은 server/.env의 GOOGLE_SERVER_API_KEY)에서 주입받는다.
    public GooglePlacesClient(RestClient.Builder builder, @Value("${google.server-api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://maps.googleapis.com").build();
        this.apiKey = apiKey;
    }

    // GoogleTranslateClient.translate()와 똑같은 이유로 똑같은 재시도 정책을 쓴다: 이 호출도
    // 앱 사용자가 화면에서 기다리는 "사용자 요청 경로"이므로, externaldata.DataGoKrHttpClient의
    // 배치용 1s/2s/4s 백오프 재시도(최대 4회 시도)를 쓰지 않는다. 대신 실패 시 대기 없이 즉시
    // 1회만 다시 시도하고, 그래도 실패하면 바로 502 Bad Gateway로 앱에 전달한다.
    // GoogleTranslateClient.translate()와 같은 이유로 Exception이 아니라 RestClientException만
    // 잡는다 — 통신 실패(4xx/5xx, 연결 실패, 타임아웃 등)만 이 재시도-후-502 정책의 대상이고,
    // callOnce() 내부의 진짜 프로그래밍 버그(예상과 다른 응답 구조로 인한 NPE 등)는 502 뒤로
    // 숨기지 않고 그대로 드러나게 한다.
    @Override
    public List<PlaceResult> nearby(double lat, double lng, int radiusMeters, PlaceCategory category) {
        try {
            return callOnce(lat, lng, radiusMeters, category);
        } catch (RestClientException firstFailure) {
            try {
                return callOnce(lat, lng, radiusMeters, category);
            } catch (RestClientException secondFailure) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "주변정보 서비스 호출 실패", secondFailure);
            }
        }
    }

    private List<PlaceResult> callOnce(double lat, double lng, int radiusMeters, PlaceCategory category) {
        JsonNode response = restClient.get()
                .uri(uriBuilder -> uriBuilder.path("/maps/api/place/nearbysearch/json")
                        .queryParam("location", lat + "," + lng)
                        .queryParam("radius", radiusMeters)
                        .queryParam("type", category.googlePlaceType())
                        .queryParam("key", apiKey)
                        .build())
                .retrieve()
                .body(JsonNode.class);

        List<PlaceResult> results = new ArrayList<>();
        for (JsonNode item : response.path("results")) {
            results.add(new PlaceResult(
                    item.path("place_id").asText(),
                    item.path("name").asText(),
                    category,
                    item.path("vicinity").asText(null),
                    item.path("geometry").path("location").path("lat").asDouble(),
                    item.path("geometry").path("location").path("lng").asDouble()
            ));
        }
        return results;
    }
}
