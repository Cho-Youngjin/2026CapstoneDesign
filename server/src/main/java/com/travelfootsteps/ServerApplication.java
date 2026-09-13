package com.travelfootsteps;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.retry.annotation.EnableRetry;
import org.springframework.scheduling.annotation.EnableScheduling;

// @SpringBootApplication은 세 애너테이션을 합쳐놓은 것이다:
// - @Configuration: 이 클래스도 @Bean을 정의할 수 있는 설정 클래스로 취급한다.
// - @EnableAutoConfiguration: 클래스패스에 있는 라이브러리(웹, JPA, 시큐리티 등)를 보고
//   필요한 빈들을 스프링이 알아서 등록해준다.
// - @ComponentScan: 이 클래스가 있는 패키지(com.travelfootsteps)와 그 하위 패키지에서
//   @Component/@Service/@Repository/@RestController/@Configuration이 붙은 클래스를 전부 찾아
//   빈으로 등록한다. 그래서 auth/country/common 패키지의 클래스들이 별도 설정 없이 자동으로 인식된다.
//
// @EnableScheduling: 이 애너테이션은 @Scheduled가 붙은 메서드들을 시간 간격에 따라 자동으로
// 실행하는 스케줄링을 활성화한다. 예를 들어 @Scheduled(fixedRate = 3600000)이면 1시간마다
// 그 메서드를 백그라운드에서 실행한다.
//
// @EnableRetry: 이 애너테이션은 @Retryable이 붙은 메서드가 실패할 때 자동으로 재시도하는
// 기능을 활성화한다. 재시도 정책(몇 번 재시도할지, 얼마나 기다릴지)은 @Retryable의 파라미터로 정의된다.
// 단, @Retryable은 프록시 기반이라 같은 클래스 내부에서 호출하는 경우 동작하지 않는다 —
// DataGoKrHttpClient는 그 문제를 피하기 위해 RetryTemplate을 직접 사용한다.
//
// @ConfigurationPropertiesScan: 이 애너테이션은 @ConfigurationProperties가 붙은 클래스들을
// 자동으로 스캔해서 빈으로 등록한다. 예를 들어 DataGoKrProperties 클래스를 찾아서
// application.yml의 data-go-kr 섹션의 값들을 자동으로 바인딩한다.
@EnableScheduling
@EnableRetry
@ConfigurationPropertiesScan
@SpringBootApplication
public class ServerApplication {

	// 스프링 부트 앱의 진입점. 내장 톰캣(웹 서버)을 띄우고,
	// 스프링 컨테이너(빈들을 관리하는 큰 상자)를 초기화한다.
	public static void main(String[] args) {
		SpringApplication.run(ServerApplication.class, args);
	}

}
