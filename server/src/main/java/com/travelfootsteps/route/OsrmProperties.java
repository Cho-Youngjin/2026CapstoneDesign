package com.travelfootsteps.route;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.Map;

// application.yml의 osrm 섹션. baseUrls는 국가 ISO 코드(KR, JP)별 OSRM 인스턴스 주소다 —
// 국가마다 다른 OSM extract를 올린 별도 인스턴스를 쓰기 때문이다(osrm/ 디렉터리 참고).
// 주소가 비어 있으면 그 국가는 지원하지 않는 것으로 취급한다.
@ConfigurationProperties(prefix = "osrm")
public record OsrmProperties(String profile, Map<String, String> baseUrls) {

    public String baseUrl(String country) {
        if (baseUrls == null || country == null) return "";
        String url = baseUrls.getOrDefault(country, "");
        return url == null ? "" : url.replaceAll("/+$", "");
    }
}
