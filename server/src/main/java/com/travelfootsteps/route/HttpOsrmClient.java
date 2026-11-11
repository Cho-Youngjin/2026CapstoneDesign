package com.travelfootsteps.route;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Profile;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.math.BigDecimal;
import java.net.URI;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.stream.Stream;

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
    // 점마다 도로를 찾는 반경(m). OSRM 기본값(약 5m)에서는 도로에서 조금만 벗어난 점이 하나만 있어도
    // NoMatch가 되어 원본 좌표가 그대로 돌아간다. 휴대폰 GPS 오차(보통 5~20m)보다 넉넉하게 잡되,
    // 너무 크면 나란한 옆 도로로 잘못 붙을 수 있어 30m로 한다.
    private static final int MATCH_RADIUS_METERS = 30;

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

    // 실시간 경로 스냅(/api/route/snap)이 쓰는 기존 방식: 모든 점에 30m 반경을 보낸다.
    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points) {
        return match(country, points, Collections.nCopies(points.size(), (double) MATCH_RADIUS_METERS), null);
    }

    // OSRM /match는 한 번에 받는 좌표 수가 제한돼 있다(osrm-routed --max-matching-size).
    // 컨트롤러는 500점까지 받는데 앱은 10m 간격으로 좌표를 쌓으므로, 1km가 넘는 평범한
    // 경로도 이 한계를 넘는다. 앞 100점만 보내고 그 결과를 "전체 경로"라고 돌려주면
    // 뒷부분이 통째로 사라지므로, 구간을 나눠 호출하고 결과를 이어 붙인다.
    // 반경·시각은 점과 짝이라 같은 경계로 함께 자른다.
    @Override
    public List<GeoPoint> match(String country, List<GeoPoint> points, List<Double> radiuses, List<Long> timestamps) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || points.size() < 2) return List.of();
        if ((radiuses != null && radiuses.size() != points.size())
                || (timestamps != null && timestamps.size() != points.size())) {
            return List.of();
        }

        List<GeoPoint> out = new ArrayList<>();
        // 구간 경계에서 선이 끊기지 않게 좌표 1점을 겹쳐서 자른다(그래서 step은 한계 - 1).
        for (int start = 0; start < points.size() - 1; start += MAX_MATCH_POINTS - 1) {
            int end = Math.min(start + MAX_MATCH_POINTS, points.size());
            List<GeoPoint> matched = matchChunk(baseUrl, points.subList(start, end),
                    radiuses == null ? null : radiuses.subList(start, end),
                    timestamps == null ? null : timestamps.subList(start, end));
            // 한 구간이라도 실패하면 전체를 실패로 다룬다 — 일부만 그리면 "성공했지만
            // 엉뚱한 경로"가 되어, 호출자가 원본 좌표로 폴백할 기회를 잃는다.
            if (matched.isEmpty()) return List.of();
            // 겹쳐 보낸 좌표 때문에 앞 구간의 끝과 이 구간의 시작이 같은 지점이다.
            out.addAll(out.isEmpty() ? matched : matched.subList(1, matched.size()));
        }
        return out;
    }

    @Override
    public List<GeoPoint> nearestCandidates(String country, GeoPoint point, int number, double maxDistanceMeters) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || number < 1) return List.of();

        JsonNode data = get(baseUrl + "/nearest/v1/" + properties.profile() + "/" + lngLat(point)
                + "?number=" + number);
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        List<GeoPoint> out = new ArrayList<>();
        for (JsonNode waypoint : data.path("waypoints")) {
            if (waypoint.path("distance").asDouble(Double.MAX_VALUE) > maxDistanceMeters) continue;
            out.add(new GeoPoint(waypoint.path("location").path(1).asDouble(),
                    waypoint.path("location").path(0).asDouble()));
        }
        return out;
    }

    // 좌표 목록에 출발점들을 먼저, 도착점들을 뒤에 넣고 sources·destinations 번호로 나눈다.
    @Override
    public List<List<Double>> table(String country, List<GeoPoint> sources, List<GeoPoint> destinations) {
        String baseUrl = properties.baseUrl(country);
        if (baseUrl.isEmpty() || sources.isEmpty() || destinations.isEmpty()) return List.of();

        String coords = Stream.concat(sources.stream(), destinations.stream())
                .map(HttpOsrmClient::lngLat).collect(Collectors.joining(";"));
        String sourceIndexes = IntStream.range(0, sources.size()).mapToObj(String::valueOf)
                .collect(Collectors.joining(";"));
        String destinationIndexes = IntStream.range(sources.size(), sources.size() + destinations.size())
                .mapToObj(String::valueOf).collect(Collectors.joining(";"));
        JsonNode data = get(baseUrl + "/table/v1/" + properties.profile() + "/" + coords
                + "?sources=" + sourceIndexes + "&destinations=" + destinationIndexes + "&annotations=distance");
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        JsonNode rows = data.path("distances");
        if (rows.size() != sources.size()) return List.of();
        List<List<Double>> out = new ArrayList<>();
        for (JsonNode row : rows) {
            if (row.size() != destinations.size()) return List.of();
            List<Double> cells = new ArrayList<>();
            // 길이 없는 칸은 JSON null이다 — 0으로 읽지 않도록 null로 둔다.
            row.forEach(cell -> cells.add(cell.isNumber() ? cell.asDouble() : null));
            out.add(cells);
        }
        return out;
    }

    private List<GeoPoint> matchChunk(String baseUrl, List<GeoPoint> chunk, List<Double> radiuses, List<Long> timestamps) {
        if (chunk.size() < 2) return List.of();
        String coords = chunk.stream().map(HttpOsrmClient::lngLat).collect(Collectors.joining(";"));
        StringBuilder url = new StringBuilder(baseUrl + "/match/v1/" + properties.profile() + "/" + coords
                + "?overview=full&geometries=geojson");
        if (radiuses != null) {
            url.append("&radiuses=").append(radiuses.stream().map(HttpOsrmClient::meters)
                    .collect(Collectors.joining(";")));
        }
        if (timestamps != null) {
            url.append("&timestamps=").append(timestamps.stream().map(String::valueOf)
                    .collect(Collectors.joining(";")));
        }
        JsonNode data = get(url.toString());
        if (data == null || !"Ok".equals(data.path("code").asText())) return List.of();

        // GPS가 끊기거나 튀는 구간이 있으면 OSRM은 궤적을 matching 여러 개로 쪼개 돌려준다.
        // 첫 번째만 쓰면 그 뒤의 경로가 통째로 사라지므로 전부 순서대로 이어 붙인다.
        List<GeoPoint> out = new ArrayList<>();
        for (JsonNode matching : data.path("matchings")) {
            out.addAll(geometry(matching.path("geometry")));
        }
        return out;
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

    // 30.0은 "30", 12.5는 "12.5"로 쓴다 — 기존 스냅 요청 URL(radiuses=30;30;...)을 그대로 지킨다.
    private static String meters(double value) {
        return BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
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
