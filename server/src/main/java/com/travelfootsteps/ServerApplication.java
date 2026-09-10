package com.travelfootsteps;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

// @SpringBootApplication은 세 애너테이션을 합쳐놓은 것이다:
// - @Configuration: 이 클래스도 @Bean을 정의할 수 있는 설정 클래스로 취급한다.
// - @EnableAutoConfiguration: 클래스패스에 있는 라이브러리(웹, JPA, 시큐리티 등)를 보고
//   필요한 빈들을 스프링이 알아서 등록해준다.
// - @ComponentScan: 이 클래스가 있는 패키지(com.travelfootsteps)와 그 하위 패키지에서
//   @Component/@Service/@Repository/@RestController/@Configuration이 붙은 클래스를 전부 찾아
//   빈으로 등록한다. 그래서 auth/country/common 패키지의 클래스들이 별도 설정 없이 자동으로 인식된다.
@SpringBootApplication
public class ServerApplication {

	// 스프링 부트 앱의 진입점. 내장 톰캣(웹 서버)을 띄우고,
	// 스프링 컨테이너(빈들을 관리하는 큰 상자)를 초기화한다.
	public static void main(String[] args) {
		SpringApplication.run(ServerApplication.class, args);
	}

}
