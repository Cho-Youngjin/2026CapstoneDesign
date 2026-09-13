package com.travelfootsteps.support;

import com.travelfootsteps.externaldata.DataGoKrHttpClient;
import com.travelfootsteps.externaldata.ExternalApiException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * DataGoKrHttpClient의 테스트용 스텁이다.
 * 배치·수집기 테스트가 실제 HTTP를 호출하지 않게 한다.
 *
 * 사용 예:
 * <pre>
 *   StubDataGoKrHttpClient client = new StubDataGoKrHttpClient();
 *   client.whenCalled("/visa", "KR", List.of(new Visa(...)));
 *   client.whenCalledFail("/alert", "JP", new ExternalApiException("API error"));
 *
 *   List<Visa> visas = client.getItems("/visa", Map.of("cond[country_iso_alp2::EQ]", "KR"), Visa.class);
 *   // visas는 위에서 설정한 목록을 반환한다.
 *
 *   client.getItems("/alert", Map.of("cond[country_iso_alp2::EQ]", "JP"), Alert.class);
 *   // ExternalApiException을 던진다.
 * </pre>
 */
public class StubDataGoKrHttpClient extends DataGoKrHttpClient {

    private final Map<String, List<?>> responses = new HashMap<>();
    private final Map<String, ExternalApiException> failures = new HashMap<>();

    // super(null, null)이 가능한 이유: DataGoKrHttpClient의 생성자가 null을 허용하고,
    // 이 클래스의 getItems()를 오버라이드하므로 실제 restClient/properties가 쓰이지 않는다.
    public StubDataGoKrHttpClient() {
        super(null, null);
    }

    /**
     * 특정 경로와 국가 코드로 호출했을 때 반환할 데이터를 설정한다.
     *
     * @param path API 상대 경로
     * @param countryIso2 국가 ISO 2-character 코드
     * @param items 반환할 아이템 목록
     */
    public <T> void whenCalled(String path, String countryIso2, List<T> items) {
        responses.put(key(path, countryIso2), items);
    }

    /**
     * 특정 경로와 국가 코드로 호출했을 때 예외를 던지도록 설정한다.
     *
     * @param path API 상대 경로
     * @param countryIso2 국가 ISO 2-character 코드
     * @param exception 던질 예외
     */
    public void whenCalledFail(String path, String countryIso2, ExternalApiException exception) {
        failures.put(key(path, countryIso2), exception);
    }

    /**
     * getItems를 오버라이드해서 실제 HTTP 호출 대신 설정된 스텁 응답을 반환한다.
     * 설정된 경로/국가가 없으면 빈 리스트를 반환한다.
     */
    @Override
    @SuppressWarnings("unchecked")
    public <T> List<T> getItems(String path, Map<String, String> queryParams, Class<T> itemType) {
        // queryParams에서 국가 코드를 추출한다.
        String countryIso2 = queryParams.getOrDefault("cond[country_iso_alp2::EQ]", "");
        String k = key(path, countryIso2);
        // 예외 설정이 있으면 던진다.
        if (failures.containsKey(k)) {
            throw failures.get(k);
        }
        // 그 외에는 설정된 응답(또는 빈 리스트)을 반환한다.
        return (List<T>) responses.getOrDefault(k, List.of());
    }

    // 경로와 국가를 조합해서 맵 키로 사용한다.
    private String key(String path, String countryIso2) {
        return path + "|" + countryIso2;
    }
}
