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
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * GoogleTranslateClientTest와 같은 이유로 존재한다 — PlacesControllerTest는 PlacesClient
 * 인터페이스를 목(mock)으로 대체하므로 재시도-후-502 정책을 전혀 통과하지 않는다. 여기서는
 * MockRestServiceServer로 실제 HTTP 계층을 흉내 내어 그 정책 자체를 검증한다.
 * 호출 대상은 Places API (New)의 searchNearby다(레거시 nearbysearch는 2025-03-01부터
 * 새 GCP 프로젝트에서 활성화할 수 없다).
 */
class GooglePlacesClientTest {

    private static final String SEARCH_NEARBY = "/v1/places:searchNearby";

    @Test
    void 두번_모두_실패하면_정확히_2번만_호출하고_502를_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        // ExpectedCount.times(2): 최초 1회 + 재시도 1회, 딱 그만큼만 허용한다.
        server.expect(ExpectedCount.times(2), requestTo(containsString(SEARCH_NEARBY)))
                .andExpect(method(HttpMethod.POST))
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

        server.expect(ExpectedCount.once(), requestTo(containsString(SEARCH_NEARBY)))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withServerError());
        server.expect(ExpectedCount.once(), requestTo(containsString(SEARCH_NEARBY)))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("""
                        {"places":[{"id":"p1","displayName":{"text":"테스트 식당","languageCode":"ko"},
                        "shortFormattedAddress":"서울",
                        "location":{"latitude":37.5,"longitude":127.0}}]}
                        """, MediaType.APPLICATION_JSON));

        List<PlaceResult> results = client.nearby(37.5, 127.0, 500, PlaceCategory.RESTAURANT);

        assertThat(results).hasSize(1);
        PlaceResult first = results.get(0);
        assertThat(first.id()).isEqualTo("p1");
        assertThat(first.name()).isEqualTo("테스트 식당");
        assertThat(first.category()).isEqualTo(PlaceCategory.RESTAURANT);
        assertThat(first.address()).isEqualTo("서울");
        assertThat(first.lat()).isEqualTo(37.5);
        assertThat(first.lng()).isEqualTo(127.0);
        server.verify();
    }

    @Test
    void 요청은_키와_필드마스크를_헤더로_보내고_카테고리와_반경을_본문에_담는다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        server.expect(ExpectedCount.once(), requestTo(containsString(SEARCH_NEARBY)))
                .andExpect(method(HttpMethod.POST))
                // 키는 URL(쿼리스트링)이 아니라 헤더로 보낸다 — URL은 접근 로그에 남기 쉽다.
                .andExpect(header("X-Goog-Api-Key", "test-key"))
                .andExpect(header("X-Goog-FieldMask", containsString("places.displayName")))
                .andExpect(jsonPath("$.includedTypes[0]").value("pharmacy"))
                // 새 API는 languageCode를 안 보내면 영어 이름을 돌려준다(Seoul 시청 근처 식당이 "Kyochon Chicken ..."로 왔다).
                .andExpect(jsonPath("$.languageCode").value("ko"))
                .andExpect(jsonPath("$.locationRestriction.circle.center.latitude").value(37.5))
                .andExpect(jsonPath("$.locationRestriction.circle.center.longitude").value(127.0))
                .andExpect(jsonPath("$.locationRestriction.circle.radius").value(500.0))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));

        client.nearby(37.5, 127.0, 500, PlaceCategory.PHARMACY);

        server.verify();
    }

    @Test
    void 주변에_장소가_없으면_places_키가_없는_응답도_빈_목록으로_처리한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesClient client = new GooglePlacesClient(builder, "test-key");

        // Places API (New)는 결과가 0건이면 {"places":[]}가 아니라 빈 객체 {}를 돌려준다.
        server.expect(ExpectedCount.once(), requestTo(containsString(SEARCH_NEARBY)))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));

        assertThat(client.nearby(37.5, 127.0, 500, PlaceCategory.ATM)).isEmpty();
        server.verify();
    }
}
