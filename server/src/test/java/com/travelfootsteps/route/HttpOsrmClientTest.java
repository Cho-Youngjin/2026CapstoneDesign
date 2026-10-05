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
}
