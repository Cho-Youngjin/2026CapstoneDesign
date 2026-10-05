package com.travelfootsteps.route;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Profile;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.net.URI;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.stream.Collectors;

// OsrmClient의 진짜 구현체(자체 호스팅 OSRM HTTP API). GooglePlacesClient와 같은 이유로
// @Profile("!test") — 테스트 프로필에서는 support.StubOsrmClient가 이 자리를 채운다.
@Component
@Profile("!test")
public class HttpOsrmClient implements OsrmClient {

    // 한 요청에 OSRM /route를 최대 8번 보내므로(OverseasWalkService) 한 호출이 오래 걸리면
    // 앱 쪽 10초 타임아웃을 금방 넘긴다. 호출당 5초로 끊는다(mock 서버와 같은 값).
    private static final Duration TIMEOUT = Duration.ofSeconds(5);
    // OSRM /match는 좌표가 너무 많으면 거부한다. mock 서버와 같은 상한.
    private static final int MAX_MATCH_POINTS = 100;

    private final RestClient restClient;
    private final OsrmProperties properties;

    // 스프링이 주입하는 RestClient.Builder는 호출마다 새로 만들어지는 prototype이라 여기서
    // requestFactory를 바꿔도 다른 클라이언트에 영향이 없다.
    @Autowired
    public HttpOsrmClient(RestClient.Builder builder, OsrmProperties properties) {
        this(builder.requestFactory(timeoutFactory()).build(), properties);
    }

    // 테스트가 MockRestServiceServer에 묶은 RestClient를 직접 넘기기 위한 생성자.
    HttpOsrmClient(RestClient restClient, OsrmProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    private static SimpleClientHttpRequestFactory timeoutFactory() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(TIMEOUT);
        factory.setReadTimeout(TIMEOUT);
        return factory;
    }

    @Override
    public Optional<GeoPoint> nearest(String country, GeoPoint point, double maxDistanceMeters) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty()) return Optional.empty();

        JsonNode data = get(baseUrl + "/nearest/v1/" + properties.profile() + "/" + lngLat(point));
        if (data == null || !"Ok".equals(data.path("code").asText())) return Optional.empty();

        JsonNode waypoint = data.path("waypoints").path(0);
        if (waypoint.isMissingNode() || waypoint.path("distance").asDouble(Double.MAX_VALUE) > maxDistanceMeters) {
            return Optional.empty();
        }
        return Optional.of(new GeoPoint(waypoint.path("location").path(1).asDouble(),
                waypoint.path("location").path(0).asDouble()));
    }

    @Override
    public List<GeoPoint> route(String country, GeoPoint from, GeoPoint to) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty()) return List.of();

        JsonNode data = get(baseUrl + "/route/v1/" + properties.profile() + "/"
                + lngLat(from) + ";" + lngLat(to) + "?overview=full&geometries=geojson");
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        return geometry(data.path("routes").path(0).path("geometry"));
    }

    // OSRM /match는 한 번에 받는 좌표 수가 제한돼 있다(osrm-routed --max-matching-size).
    // 컨트롤러는 500점까지 받는데 앱은 10m 간격으로 좌표를 쌓으므로, 1km가 넘는 평범한
    // 경로도 이 한계를 넘는다. 앞 100점만 보내고 그 결과를 "전체 경로"라고 돌려주면
    // 뒷부분이 통째로 사라지므로, 구간을 나눠 호출하고 결과를 이어 붙인다.
    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || points.size() < 2) return List.of();

        List<GeoPoint> out = new ArrayList<>();
        // 구간 경계에서 선이 끊기지 않게 좌표 1점을 겹쳐서 자른다(그래서 step은 한계 - 1).
        for (int start = 0; start < points.size() - 1; start += MAX_MATCH_POINTS - 1) {
            List<GeoPoint> chunk =
                    points.subList(start, Math.min(start + MAX_MATCH_POINTS, points.size()));
            List<GeoPoint> matched = matchChunk(baseUrl, chunk);
            // 한 구간이라도 실패하면 전체를 실패로 다룬다 — 일부만 그리면 "성공했지만
            // 엉뚱한 경로"가 되어, 호출자가 원본 좌표로 폴백할 기회를 잃는다.
            if (matched.isEmpty()) return List.of();
            // 겹쳐 보낸 좌표 때문에 앞 구간의 끝과 이 구간의 시작이 같은 지점이다.
            out.addAll(out.isEmpty() ? matched : matched.subList(1, matched.size()));
        }
        return out;
    }

    private List<GeoPoint> matchChunk(String baseUrl, List<GeoPoint> chunk) {
        if (chunk.size() < 2) return List.of();
        String coords = chunk.stream().map(HttpOsrmClient::lngLat).collect(Collectors.joining(";"));
        JsonNode data = get(baseUrl + "/match/v1/" + properties.profile() + "/" + coords
                + "?overview=full&geometries=geojson");
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        return geometry(data.path("matchings").path(0).path("geometry"));
    }

    // 실패(연결 거부, 타임아웃, 4xx/5xx, JSON 아님)는 전부 null로 바꾼다 — OsrmClient 주석 참고.
    // OSRM은 도로를 못 찾았을 때도 HTTP 400에 {"code":"NoRoute"}를 주므로 정상적인 경우다.
    private JsonNode get(String url) {
        try {
            return restClient.get().uri(URI.create(url)).retrieve()
                    .onStatus(status -> true, (request, response) -> { })
                    .body(JsonNode.class);
        } catch (RestClientException e) {
            return null;
        }
    }

    // OSRM은 lon,lat 순서를 쓴다(Google과 반대). 소수 7자리면 약 1cm 정밀도다.
    private static String lngLat(GeoPoint p) {
        return String.format(Locale.ROOT, "%.7f,%.7f", p.lng(), p.lat());
    }

    // GeoJSON LineString은 [lng, lat] 순서다 — 우리 응답 스키마({lat, lng})로 뒤집는다.
    private static List<GeoPoint> geometry(JsonNode geometry) {
        List<GeoPoint> out = new ArrayList<>();
        for (JsonNode c : geometry.path("coordinates")) {
            out.add(new GeoPoint(c.path(1).asDouble(), c.path(0).asDouble()));
        }
        return out;
    }
}
