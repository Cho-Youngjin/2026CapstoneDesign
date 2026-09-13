package com.travelfootsteps.auth;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

// @EnableWebSecurity: 스프링 시큐리티의 웹 보안 기능을 켠다는 선언이다. 이게 있어야
// 아래 SecurityFilterChain 빈이 실제 필터 체인 설정으로 동작한다.
// 주의: 이 클래스는 "SecurityFilterChain을 리턴하는 @Bean 메서드가 있는 평범한 @Configuration"이라서,
// @WebMvcTest처럼 컨트롤러 계층만 가볍게 띄우는 테스트에서는 자동으로 로딩되지 않는다.
// 그런 테스트에서 이 설정을 실제로 검증하려면 @Import(SecurityConfig.class)로 명시적으로 끼워 넣어야 한다.
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    // 이 앱의 HTTP 보안 규칙 전체를 정의하는 빈. HttpSecurity는 스프링이 제공하는 빌더로,
    // 메서드를 체이닝하면서 규칙을 하나씩 쌓고 마지막에 build()로 완성한다.
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http, TokenVerifier tokenVerifier)
            throws Exception {
        return http
                // CSRF(Cross-Site Request Forgery) 보호는 "브라우저가 쿠키로 세션을 유지하는"
                // 전통적인 웹앱에서 필요하다. 우리는 세션을 안 쓰고 매 요청마다 토큰으로 인증하므로
                // CSRF 공격 시나리오 자체가 성립하지 않아 꺼둔다.
                .csrf(csrf -> csrf.disable())
                // STATELESS: 서버가 로그인 상태를 세션에 저장하지 않는다는 뜻이다.
                // 매 요청마다 클라이언트가 Authorization 헤더로 자기 자신을 다시 증명해야 하며,
                // 그래서 서버를 여러 대로 늘려도(스케일 아웃) 세션 동기화 문제가 없다.
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // 경로별 접근 규칙. 위에서부터 순서대로 매칭되며, 먼저 매칭되는 규칙이 적용된다.
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/health").permitAll()   // 헬스체크는 로그인 없이 허용
                        .requestMatchers("/api/**").authenticated()   // 그 외 /api/**는 로그인 필요
                        // Spring Security 6부터 AuthorizationFilter가 기본적으로 모든 디스패치 타입에
                        // 적용되는데, 여기에는 컨트롤러가 예외를 던졌을 때 스프링 부트가 /error로
                        // 다시 요청을 보내는 내부 ERROR 디스패치도 포함된다. 이 줄이 없으면 그 ERROR
                        // 디스패치까지 아래 denyAll()에 걸려서, 진짜 500 에러가 403으로 둔갑해버린다.
                        .requestMatchers("/error").permitAll()
                        // WebSocket(STOMP) 핸드셰이크 엔드포인트. /api/** 패턴 밖이라 원래도 여기서
                        // 막히거나 뚫리거나 둘 중 하나인데, 실제 사용자 인증은 이 HTTP 레벨이 아니라
                        // STOMP CONNECT 프레임 단계(Task 10의 StompAuthChannelInterceptor, Authorization
                        // 네이티브 헤더 검증)에서 별도로 수행되므로 이 HTTP Upgrade 요청 자체는 통과시킨다.
                        // permitAll이라고 해서 인증이 생략되는 게 아니다 — "HTTP 핸드셰이크 레벨에는
                        // 검사할 필요가 없고, 그 다음 계층(STOMP)에서 반드시 검사한다"는 역할 분담이다.
                        // /ws/** 로만 정확히 스코프돼 있어 /api/** 인증 요구사항에는 영향이 없다.
                        .requestMatchers("/ws/**").permitAll()
                        .anyRequest().denyAll())                      // 정의되지 않은 나머지는 전부 거부
                // 인증이 안 된 요청이 위 authenticated() 규칙에 걸리면, 스프링 시큐리티가 이 지점에서
                // 401 Unauthorized로 응답하도록 지정한다. FirebaseAuthFilter는 401을 직접 만들지 않고
                // 이 설정에 처리를 맡긴다.
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
                // 우리가 만든 FirebaseAuthFilter를, 스프링 시큐리티가 기본 제공하는
                // UsernamePasswordAuthenticationFilter보다 먼저 실행되도록 필터 체인에 끼워 넣는다.
                // 그래야 컨트롤러에 도달하기 전에 Authorization 헤더를 먼저 읽어 로그인 처리를 마칠 수 있다.
                .addFilterBefore(new FirebaseAuthFilter(tokenVerifier),
                        UsernamePasswordAuthenticationFilter.class)
                .build();
    }
}
