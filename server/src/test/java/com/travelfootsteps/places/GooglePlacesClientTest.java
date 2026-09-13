package com.travelfootsteps.places;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * GoogleTranslateClientTest와 같은 이유로 존재한다 — PlacesControllerTest는 PlacesClient
 * 인터페이스를 목(mock)으로 대체하므로 재시도-후-502 정책을 전혀 통과하지 않는다. 여기서는
 * MockRestServiceServer로 실제 HTTP 계층을 흉내 내어 그 정책 자체를 검증한다.
 */
class GooglePlacesClientTest {

    @Test
    void 두번_모두_실패하면_정확히_2번만_호출하고_502를_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        // ExpectedCount.times(2): 최초 1회 + 재시도 1회, 딱 그만큼만 허용한다.
        server.expect(ExpectedCount.times(2), requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withServerError());

        assertThatThrownBy(() -> client.nearby(37.5, 127.0, 500, PlaceCategory.RESTAURANT))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> assertThat(((ResponseStatusException) e).getStatusCode())
                        .isEqualTo(HttpStatus.BAD_GATEWAY));

        server.verify();
    }

    @Test
    void 첫번째_시도만_실패하고_재시도가_성공하면_정상_목록을_반환한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(), requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withServerError());
        server.expect(ExpectedCount.once(), requestTo(containsString("/maps/api/place/nearbysearch/json")))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"results":[{"place_id":"p1","name":"테스트 식당","vicinity":"서울",
                        "geometry":{"location":{"lat":37.5,"lng":127.0}}}]}
                        """, MediaType.APPLICATION_JSON));

        List<PlaceResult> results = client.nearby(37.5, 127.0, 500, PlaceCategory.RESTAURANT);

        assertThat(results).hasSize(1);
        assertThat(results.get(0).name()).isEqualTo("테스트 식당");
        server.verify();
    }
}
