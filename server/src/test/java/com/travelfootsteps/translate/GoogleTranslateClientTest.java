package com.travelfootsteps.translate;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * GoogleTranslateClient는 스프링 컨텍스트 없이도(순수 자바 객체로) 테스트할 수 있다 —
 * 생성자가 RestClient.Builder와 문자열 하나만 받기 때문이다. 여기서는 MockRestServiceServer로
 * 실제 HTTP 통신 계층을 가짜로 흉내 내서, "실패 시 정확히 1번만 재시도하고 그래도 실패하면
 * 502를 던진다"는 재시도 정책 자체를 직접 검증한다. 컨트롤러 테스트(TranslateControllerTest)는
 * TranslationClient 인터페이스를 목(mock)으로 대체하기 때문에 이 정책을 전혀 통과하지 않는다 —
 * 그래서 이 클래스가 별도로 필요하다.
 */
class GoogleTranslateClientTest {

    @Test
    void 두번_모두_실패하면_정확히_2번만_호출하고_502를_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GoogleTranslateClient client = new GoogleTranslateClient(builder, "test-key");

        // ExpectedCount.times(2): 정확히 2번(최초 1회 + 재시도 1회) 요청되어야 한다는 뜻이다.
        // 3번째 요청이 오면(=재시도를 두 번 이상 했다면) MockRestServiceServer가 실패시킨다.
        server.expect(ExpectedCount.times(2), requestTo(containsString("/language/translate/v2")))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withServerError());

        assertThatThrownBy(() -> client.translate("안녕", "en", null))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(e -> assertThat(((ResponseStatusException) e).getStatusCode())
                        .isEqualTo(HttpStatus.BAD_GATEWAY));

        // 위에서 설정한 ExpectedCount.times(2)가 실제로 정확히 채워졌는지(더 적지도, 더 많지도
        // 않게) 검증한다 — 이 한 줄이 "재시도 횟수가 딱 1번"이라는 정책을 실제로 증명한다.
        server.verify();
    }

    @Test
    void 첫번째_시도만_실패하고_재시도가_성공하면_정상_번역결과를_반환한다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GoogleTranslateClient client = new GoogleTranslateClient(builder, "test-key");

        server.expect(ExpectedCount.once(), requestTo(containsString("/language/translate/v2")))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withServerError());
        server.expect(ExpectedCount.once(), requestTo(containsString("/language/translate/v2")))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("""
                        {"data":{"translations":[{"translatedText":"Hello","detectedSourceLanguage":"ko"}]}}
                        """, MediaType.APPLICATION_JSON));

        TranslationResult result = client.translate("안녕하세요", "en", null);

        assertThat(result.translatedText()).isEqualTo("Hello");
        assertThat(result.detectedSourceLanguage()).isEqualTo("ko");
        server.verify();
    }
}
