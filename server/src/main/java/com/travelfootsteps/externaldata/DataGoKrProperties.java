package com.travelfootsteps.externaldata;

import org.springframework.boot.context.properties.ConfigurationProperties;

// @ConfigurationProperties(prefix = "data-go-kr")는 이 클래스가 application.yml의
// data-go-kr 섹션과 자동으로 바인딩되는 설정 클래스임을 의미한다.
// 예를 들어 application.yml에 다음과 같이 정의되면:
//   data-go-kr:
//     service-key: ${DATA_GO_KR_SERVICE_KEY:}
// 이 클래스의 serviceKey 필드에 그 값이 자동으로 주입된다.
//
// record는 자바 14+ 문법으로, 불변 데이터 클래스다. 자동으로 생성자, getter, equals,
// hashCode, toString을 만들어준다. 설정 바인딩에 record를 쓸 때는
// ServerApplication에 @ConfigurationPropertiesScan이 있어야 작동한다.
@ConfigurationProperties(prefix = "data-go-kr")
public record DataGoKrProperties(String serviceKey) {
}
