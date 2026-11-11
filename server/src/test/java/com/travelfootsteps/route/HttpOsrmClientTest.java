package com.travelfootsteps.route;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

// OSRM 응답 해석(lon,lat → lat,lng 뒤집기)과 "실패는 예외가 아니라 빈 결과" 정책을 검증한다.
class HttpOsrmClientTest {

    private static final OsrmProperties PROPS =
            new OsrmProperties("foot", Map.of("JP", "http://jp.osrm:5002/", "KR", ""));

    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final HttpOsrmClient client = new HttpOsrmClient(builder.build(), PROPS);

    @Test
    void nearest는_도로_위_좌표를_lat_lng_순서로_돌려준다() {
        server.expect(requestTo("http://jp.osrm:5002/nearest/v1/foot/139.7671000,35.6812000"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","waypoints":[{"distance":12.5,"location":[139.7672,35.6811]}]}
                        """, MediaType.APPLICATION_JSON));

        Optional<GeoPoint> snapped = client.nearest("JP", new GeoPoint(35.6812, 139.7671), 50);

        assertThat(snapped).contains(new GeoPoint(35.6811, 139.7672));
    }

    @Test
    void nearest는_도로가_기준거리보다_멀면_비어_있다() {
        server.expect(requestTo("http://jp.osrm:5002/nearest/v1/foot/139.7671000,35.6812000"))
                .andRespond(withSuccess("""
                        {"code":"Ok","waypoints":[{"distance":80.0,"location":[139.7672,35.6811]}]}
                        """, MediaType.APPLICATION_JSON));

        assertThat(client.nearest("JP", new GeoPoint(35.6812, 139.7671), 50)).isEmpty();
    }

    @Test
    void route는_GeoJSON_좌표를_lat_lng으로_뒤집어_돌려준다() {
        server.expect(requestTo("http://jp.osrm:5002/route/v1/foot/139.7000000,35.6000000;139.7100000,35.6100000"
                        + "?overview=full&geometries=geojson"))
                .andRespond(withSuccess("""
                        {"code":"Ok","routes":[{"geometry":{"coordinates":[[139.7,35.6],[139.705,35.605]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> route = client.route("JP", new GeoPoint(35.6, 139.7), new GeoPoint(35.61, 139.71));

        assertThat(route).containsExactly(new GeoPoint(35.6, 139.7), new GeoPoint(35.605, 139.705));
    }

    @Test
    void OSRM이_NoRoute_400이나_서버오류를_주면_예외_없이_빈_결과다() {
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/route/v1/")))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"code\":\"NoRoute\"}"));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/route/v1/")))
                .andRespond(withServerError());

        GeoPoint a = new GeoPoint(35.6, 139.7);
        GeoPoint b = new GeoPoint(35.61, 139.71);
        assertThat(client.route("JP", a, b)).isEmpty();
        assertThat(client.route("JP", a, b)).isEmpty();
    }

    @Test
    void 주소가_없거나_모르는_국가면_호출하지_않고_빈_결과다() {
        GeoPoint a = new GeoPoint(35.6, 139.7);

        assertThat(client.route("KR", a, a)).isEmpty();
        assertThat(client.route("XX", a, a)).isEmpty();
        assertThat(client.nearest("KR", a, 50)).isEmpty();
        assertThat(client.match("KR", List.of(a, a))).isEmpty();
        server.verify(); // 기대한 요청이 하나도 없으므로 실제 호출이 있었다면 여기서 실패한다
    }

    @Test
    void match는_OSRM_좌표_한계를_넘는_궤적을_나눠_보내고_결과를_이어_붙인다() {
        // 앱은 10m 간격으로 좌표를 쌓으므로 1km가 넘는 평범한 경로도 100점을 넘는다.
        // 앞 100점만 보내고 그 결과를 "전체 경로"로 돌려주면 뒷부분이 통째로 사라진다.
        List<GeoPoint> trace = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            trace.add(new GeoPoint(35.0 + i * 0.0001, 139.0 + i * 0.0001));
        }

        server.expect(ExpectedCount.times(2), requestTo(startsWith("http://jp.osrm:5002/match/v1/foot/")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP", trace);

        server.verify();
        // 두 구간이 좌표 1점을 공유하므로 이어 붙일 때 중복 하나를 떼어낸다: 2 + (2 - 1).
        assertThat(matched).hasSize(3);
    }

    @Test
    void match는_점마다_30m_탐색_반경을_보내_도로에서_조금_벗어난_GPS도_붙인다() {
        // OSRM 기본 반경(약 5m)에서는 도로에서 조금만 벗어난 점이 하나만 있어도 NoMatch로 거절돼
        // 서버가 원본 좌표를 돌려주고, 앱 지도에는 도로를 무시한 직선이 그려진다.
        server.expect(requestTo(containsString("radiuses=30;30;30")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP", List.of(
                new GeoPoint(35.0, 139.0), new GeoPoint(35.05, 139.05), new GeoPoint(35.1, 139.1)));

        server.verify();
        assertThat(matched).hasSize(2);
    }

    @Test
    void nearestCandidates는_number개를_요청하고_기준거리_안의_점만_가까운_순으로_돌려준다() {
        server.expect(requestTo("http://jp.osrm:5002/nearest/v1/foot/139.7671000,35.6812000?number=5"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","waypoints":[
                          {"distance":3.0,"location":[139.7672,35.6811]},
                          {"distance":40.0,"location":[139.7675,35.6815]},
                          {"distance":250.0,"location":[139.7700,35.6830]}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> candidates = client.nearestCandidates("JP", new GeoPoint(35.6812, 139.7671), 5, 200);

        assertThat(candidates).containsExactly(new GeoPoint(35.6811, 139.7672), new GeoPoint(35.6815, 139.7675));
    }

    @Test
    void table은_출발점과_도착점을_번호로_나눠_거리표를_받고_길이_없는_칸은_null이다() {
        server.expect(requestTo("http://jp.osrm:5002/table/v1/foot/"
                        + "139.0000000,35.0000000;139.0010000,35.0000000;139.0020000,35.0000000;139.0030000,35.0000000"
                        + "?sources=0;1&destinations=2;3&annotations=distance"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","distances":[[10.5,null],[20,30.25]]}
                        """, MediaType.APPLICATION_JSON));

        List<List<Double>> table = client.table("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.0, 139.001)),
                List.of(new GeoPoint(35.0, 139.002), new GeoPoint(35.0, 139.003)));

        assertThat(table).hasSize(2);
        assertThat(table.get(0)).containsExactly(10.5, null);
        assertThat(table.get(1)).containsExactly(20.0, 30.25);
    }

    @Test
    void table은_OSRM이_실패하거나_표_모양이_다르면_빈_결과다() {
        server.expect(requestTo(startsWith("http://jp.osrm:5002/table/v1/foot/")))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"code\":\"InvalidQuery\"}"));
        server.expect(requestTo(startsWith("http://jp.osrm:5002/table/v1/foot/")))
                .andRespond(withSuccess("{\"code\":\"Ok\",\"distances\":[[1.0]]}", MediaType.APPLICATION_JSON));

        List<GeoPoint> two = List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.0, 139.001));
        assertThat(client.table("JP", two, two)).isEmpty();
        assertThat(client.table("JP", two, two)).isEmpty();
    }

    @Test
    void match에_점마다_반경과_시각을_넘기면_radiuses와_timestamps로_보낸다() {
        server.expect(requestTo(containsString("radiuses=5;12.5;50&timestamps=100;160;220&gaps=ignore")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.05, 139.05), new GeoPoint(35.1, 139.1)),
                List.of(5.0, 12.5, 50.0), List.of(100L, 160L, 220L));

        server.verify();
        assertThat(matched).hasSize(2);
    }

    @Test
    void match에_반경과_시각이_없으면_OSRM_기본값을_쓰도록_옵션을_보내지_않는다() {
        server.expect(requestTo("http://jp.osrm:5002/match/v1/foot/139.0000000,35.0000000;139.1000000,35.1000000"
                        + "?overview=full&geometries=geojson"))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1)), null, null);

        server.verify();
        assertThat(matched).hasSize(2);
    }

    @Test
    void match에_반경이나_시각의_개수가_점과_다르면_호출하지_않고_빈_결과다() {
        List<GeoPoint> two = List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1));

        assertThat(client.match("JP", two, List.of(5.0), null)).isEmpty();
        assertThat(client.match("JP", two, null, List.of(1L, 2L, 3L))).isEmpty();
        server.verify();
    }

    @Test
    void match에_반경이_null이나_NaN이면_예외_없이_호출하지_않고_빈_결과다() {
        List<GeoPoint> two = List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1));
        List<Double> withNull = new ArrayList<>();
        withNull.add(5.0);
        withNull.add(null);

        assertThat(client.match("JP", two, withNull, null)).isEmpty();
        assertThat(client.match("JP", two, List.of(5.0, Double.NaN), null)).isEmpty();
        server.verify();
    }

    @Test
    void match는_궤적을_나눠_보낼_때_반경과_시각도_같은_경계로_자른다() {
        // 150점: 첫 구간은 0~99번, 둘째 구간은 99~149번(1점 겹침). 반경·시각이 점과 어긋나면 둘째 구간이 99번이
        // 아닌 값으로 시작한다.
        List<GeoPoint> trace = new ArrayList<>();
        List<Double> radiuses = new ArrayList<>();
        List<Long> timestamps = new ArrayList<>();
        for (int i = 0; i < 150; i++) {
            trace.add(new GeoPoint(35.0 + i * 0.0001, 139.0 + i * 0.0001));
            radiuses.add(5.0 + i);
            timestamps.add(1000L + i);
        }
        String ok = """
                {"code":"Ok","matchings":[{"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}}]}
                """;
        server.expect(requestTo(containsString("radiuses=5;6;7;")))
                .andExpect(requestTo(containsString("timestamps=1000;1001;")))
                .andRespond(withSuccess(ok, MediaType.APPLICATION_JSON));
        server.expect(requestTo(containsString("radiuses=104;105;")))
                .andExpect(requestTo(containsString("timestamps=1099;1100;")))
                .andRespond(withSuccess(ok, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP", trace, radiuses, timestamps);

        server.verify();
        assertThat(matched).hasSize(3);
    }

    @Test
    void nearestCandidates는_OSRM이_실패하거나_number가_1보다_작으면_빈_결과다() {
        server.expect(requestTo(startsWith("http://jp.osrm:5002/nearest/v1/foot/")))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"code\":\"NoSegment\"}"));

        assertThat(client.nearestCandidates("JP", new GeoPoint(35.0, 139.0), 5, 200)).isEmpty();
        assertThat(client.nearestCandidates("JP", new GeoPoint(35.0, 139.0), 0, 200)).isEmpty();
        server.verify();
    }

    @Test
    void match는_OSRM이_궤적을_여러_matching으로_나눠_주면_전부_이어_붙인다() {
        // GPS가 끊기거나 튀는 구간이 있으면 OSRM은 궤적을 matching 여러 개로 쪼개 돌려준다.
        // 첫 번째만 쓰면 그 뒤의 이동 경로가 통째로 사라진다.
        server.expect(requestTo(startsWith("http://jp.osrm:5002/match/v1/foot/")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"code":"Ok","matchings":[
                          {"geometry":{"coordinates":[[139.0,35.0],[139.1,35.1]]}},
                          {"geometry":{"coordinates":[[139.2,35.2],[139.3,35.3]]}}
                        ]}
                        """, MediaType.APPLICATION_JSON));

        List<GeoPoint> matched = client.match("JP",
                List.of(new GeoPoint(35.0, 139.0), new GeoPoint(35.3, 139.3)));

        server.verify();
        assertThat(matched).containsExactly(
                new GeoPoint(35.0, 139.0), new GeoPoint(35.1, 139.1),
                new GeoPoint(35.2, 139.2), new GeoPoint(35.3, 139.3));
    }
}
