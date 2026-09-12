package com.travelfootsteps.alert;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

// @Component: 스프링 빈으로 등록해서 TravelAlertCollector가 생성자 주입으로 받아 쓸 수 있게 한다.
// 이 클래스는 "외교부 여행경보 조회 API를 어떻게 호출하는가"만 알고, 응답을 어떻게 해석해서
// DB에 저장할지는 전혀 모른다(그건 TravelAlertCollector의 책임) — 관심사 분리.
@Component
public class TravelAlertClient {

    // 공공데이터포털에 등록된 여행경보 목록 조회 API의 상대 경로.
    private static final String PATH = "/1262000/TravelAlarmService2/getTravelAlarmList2";

    private final DataGoKrHttpClient httpClient;

    public TravelAlertClient(DataGoKrHttpClient httpClient) {
        this.httpClient = httpClient;
    }

    public List<TravelAlertApiItem> fetch(String countryIsoAlpha2) {
        return httpClient.getItems(
                PATH,
                Map.of("numOfRows", "20", "pageNo", "1", "cond[country_iso_alp2::EQ]", countryIsoAlpha2),
                TravelAlertApiItem.class
        );
    }
}
