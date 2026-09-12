package com.travelfootsteps.visa;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.Optional;

// @Component: 이 클래스를 스프링 빈으로 등록한다. 생성자에 DataGoKrHttpClient가 필요하면
// 스프링이 자동으로 의존성을 주입해준다(생성자 주입). 이 클래스는 "외교부 입국허가요건 API 전용"
// 얇은 래퍼다 — 실제 HTTP/재시도/파싱은 Task 1의 DataGoKrHttpClient가 전부 담당하고,
// 여기서는 이 API에 특화된 경로·쿼리 파라미터·응답 타입만 고정해서 넘겨준다.
// 요청/배치 흐름에서의 위치: VisaRequirementCollector가 이 클래스를 호출 -> 이 클래스가
// DataGoKrHttpClient를 호출 -> 실제 data.go.kr 서버로 HTTP 요청이 나간다.
@Component
public class EntranceVisaClient {

    // 실제 API 응답 확인 필요: 이 경로와 쿼리 파라미터 이름은 Phase 0 Task 2 Step 2가 검증한 값과
    // 동일하다. 활용가이드 문서의 실제 값이 다르면 이 상수만 바꾸면 되고, 나머지 코드(수집기 등)는
    // 영향받지 않는다.
    private static final String PATH = "/1262000/EntranceVisaService2/getEntranceVisaList2";

    private final DataGoKrHttpClient httpClient;

    public EntranceVisaClient(DataGoKrHttpClient httpClient) {
        this.httpClient = httpClient;
    }

    /**
     * 국가 ISO 2자리 코드로 입국허가요건 한 건을 조회한다.
     * 이 API는 국가 코드로 필터링하면 보통 한 건만 반환되므로 첫 번째 항목만 취한다.
     *
     * @param countryIsoAlpha2 국가 ISO 3166-1 alpha-2 코드 (예: "VN")
     * @return 조회된 항목. 응답이 비어있으면 Optional.empty().
     * @throws com.travelfootsteps.externaldata.ExternalApiException 재시도(최대 3회) 후에도 호출이 실패한 경우.
     *         호출부(VisaRequirementCollector)가 이 예외를 잡아서 그 국가만 건너뛴다.
     */
    public Optional<EntranceVisaApiItem> fetch(String countryIsoAlpha2) {
        List<EntranceVisaApiItem> items = httpClient.getItems(
                PATH,
                Map.of(
                        "numOfRows", "10",
                        "pageNo", "1",
                        "cond[country_iso_alp2::EQ]", countryIsoAlpha2
                ),
                EntranceVisaApiItem.class
        );
        return items.stream().findFirst();
    }
}
