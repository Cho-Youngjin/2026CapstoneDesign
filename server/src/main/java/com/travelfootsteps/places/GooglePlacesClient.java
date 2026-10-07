package com.travelfootsteps.places;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

// PlacesClient 인터페이스의 "진짜" 구현체. Google Places API (New)의 Nearby Search를 호출한다.
// 예전에는 레거시 엔드포인트(/maps/api/place/nearbysearch/json)를 썼지만, 2025-03-01부터 새로 만든
// GCP 프로젝트는 레거시 Places API를 활성화할 수 없다. 게다가 레거시는 키가 거부돼도 HTTP 200에
// "status":"REQUEST_DENIED"를 담아 돌려줘서, 결과 목록만 읽던 예전 코드는 에러를 "주변에 장소 없음"으로
// 조용히 삼켰다. 새 API는 거부 시 진짜 HTTP 4xx를 돌려주므로 아래 재시도-후-502 정책에 그대로 걸린다.
// @Component + @Profile("!test")는 GoogleTranslateClient와 같은 이유다 — 테스트 프로필에서는
// 이 빈이 생기지 않고, 테스트 코드가 등록한 Mockito 목이 대신 PlacesClient 자리를 채운다.
@Component
@Profile("!test")
public class GooglePlacesClient implements PlacesClient {

    // 새 API는 응답에 "어떤 필드를 돌려줄지"를 헤더(X-Goog-FieldMask)로 반드시 지정해야 한다 —
    // 안 보내면 400이 난다. 필요한 필드만 고르면 응답이 작아지고 과금 등급(SKU)도 낮아진다.
    private static final String FIELD_MASK =
            "places.id,places.displayName,places.shortFormattedAddress,places.location";

    // 새 API의 maxResultCount 허용 범위는 1~20이고 기본값도 20이다. 레거시가 한 번에 최대 20개를
    // 돌려주던 것과 같은 동작을 명시적으로 고정해 둔다.
    private static final int MAX_RESULT_COUNT = 20;

    private final RestClient restClient;
    private final String apiKey;

    // GoogleTranslateClient와 동일하게, API 키는 코드에 적지 않고 application.yml
    // (google.server-api-key, 실제 값은 server/.env의 GOOGLE_SERVER_API_KEY)에서 주입받는다.
    public GooglePlacesClient(RestClient.Builder builder, @Value("${google.server-api-key}") String apiKey) {
        this.restClient = builder.baseUrl("https://places.googleapis.com").build();
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
        // 레거시는 GET + 쿼리스트링이었지만 새 API는 POST + JSON 본문이다. 키도 URL이 아니라
        // X-Goog-Api-Key 헤더로 보낸다 — URL은 서버/프록시 접근 로그에 남기 쉬워서 키가 새기 쉽다.
        // 반경(radius)은 double이어야 하고 0보다 커야 한다(최대 50000m).
        // languageCode: 장소 이름·주소를 어떤 언어로 받을지 정한다. 안 보내면 새 API는 영어로 돌려주므로
        // (서울 시내 식당이 "Kyochon Chicken ..."으로 내려왔다) 한국어 앱에 맞춰 "ko"를 명시한다.
        // 한국어 이름이 없는 해외 장소는 Google이 알아서 현지어/음역 이름으로 채워 준다.
        Map<String, Object> body = Map.of(
                "includedTypes", List.of(category.googlePlaceType()),
                "languageCode", "ko",
                "maxResultCount", MAX_RESULT_COUNT,
                "locationRestriction", Map.of("circle", Map.of(
                        "center", Map.of("latitude", lat, "longitude", lng),
                        "radius", (double) radiusMeters)));

        JsonNode response = restClient.post()
                .uri("/v1/places:searchNearby")
                .header("X-Goog-Api-Key", apiKey)
                .header("X-Goog-FieldMask", FIELD_MASK)
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .retrieve()
                .body(JsonNode.class);

        // 결과가 0건이면 새 API는 {"places":[]}가 아니라 빈 객체 {}를 돌려준다. path()는 키가
        // 없으면 null이 아니라 "빈 노드"를 돌려주므로, 따로 null 검사 없이 for문이 0번 돈다.
        List<PlaceResult> results = new ArrayList<>();
        for (JsonNode item : response.path("places")) {
            results.add(new PlaceResult(
                    item.path("id").asText(),
                    item.path("displayName").path("text").asText(),
                    category,
                    item.path("shortFormattedAddress").asText(null),
                    item.path("location").path("latitude").asDouble(),
                    item.path("location").path("longitude").asDouble()
            ));
        }
        return results;
    }
}
