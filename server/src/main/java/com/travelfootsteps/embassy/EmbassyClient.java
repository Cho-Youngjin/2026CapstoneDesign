package com.travelfootsteps.embassy;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

// @Component: 스프링 빈으로 등록해서 EmbassyCollector가 생성자 주입으로 받아 쓸 수 있게 한다.
@Component
public class EmbassyClient {

    private static final String PATH = "/1262000/EmbassyService2/getEmbassyList2";

    private final DataGoKrHttpClient httpClient;

    public EmbassyClient(DataGoKrHttpClient httpClient) {
        this.httpClient = httpClient;
    }

    public List<EmbassyApiItem> fetch(String countryIsoAlpha2) {
        return httpClient.getItems(
                PATH,
                Map.of("numOfRows", "20", "pageNo", "1", "cond[country_iso_alp2::EQ]", countryIsoAlpha2),
                EmbassyApiItem.class
        );
    }
}
