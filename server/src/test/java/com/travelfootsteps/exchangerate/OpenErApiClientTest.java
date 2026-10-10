package com.travelfootsteps.exchangerate;

import com.travelfootsteps.externaldata.ExternalApiException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class OpenErApiClientTest {

    @Test
    void KRW_기준_환율과_갱신_시각을_읽는다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        OpenErApiClient client = new OpenErApiClient(builder);

        server.expect(requestTo("https://open.er-api.com/v6/latest/KRW"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"result":"success","base_code":"KRW","time_last_update_unix":1791504151,
                         "rates":{"KRW":1,"VND":19.255146,"TWD":0.023826}}
                        """, MediaType.APPLICATION_JSON));

        OpenErApiResponse response = client.fetchKrwBase();

        assertThat(response.timeLastUpdateUnix()).isEqualTo(1791504151L);
        assertThat(response.rates().get("VND")).isEqualByComparingTo("19.255146");
        assertThat(response.rates().get("TWD")).isEqualByComparingTo("0.023826");
        server.verify();
    }

    @Test
    void result가_success가_아니면_ExternalApiException을_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        OpenErApiClient client = new OpenErApiClient(builder);

        server.expect(requestTo("https://open.er-api.com/v6/latest/KRW"))
                .andRespond(withSuccess("{\"result\":\"error\",\"error-type\":\"unsupported-code\"}",
                        MediaType.APPLICATION_JSON));

        assertThatThrownBy(client::fetchKrwBase).isInstanceOf(ExternalApiException.class);
    }

    @Test
    void HTTP_오류면_ExternalApiException을_던진다() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        OpenErApiClient client = new OpenErApiClient(builder);

        server.expect(requestTo("https://open.er-api.com/v6/latest/KRW")).andRespond(withServerError());

        assertThatThrownBy(client::fetchKrwBase).isInstanceOf(ExternalApiException.class);
    }
}
