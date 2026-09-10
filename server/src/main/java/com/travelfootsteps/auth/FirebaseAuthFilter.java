package com.travelfootsteps.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

// 서블릿 필터: 컨트롤러(@RestController)에 요청이 도착하기 "전에" 실행되는 코드다.
// 스프링 시큐리티는 여러 필터를 체인(사슬)처럼 연결해두고, 요청이 그 사슬을 순서대로 통과하게 한다.
// 이 필터는 SecurityConfig에서 UsernamePasswordAuthenticationFilter 앞에 끼워 넣어서,
// 스프링 시큐리티의 기본 인증 처리보다 먼저 "Authorization 헤더를 보고 로그인 처리를 해버리는" 역할을 한다.
@Slf4j
@RequiredArgsConstructor // Lombok: final 필드(tokenVerifier)를 받는 생성자를 자동으로 만들어준다.
public class FirebaseAuthFilter extends OncePerRequestFilter {
    // OncePerRequestFilter를 상속하면, 하나의 요청 안에서 필터가 여러 번 중복 실행되지 않도록
    // 스프링이 보장해준다 (내부적으로 forward/include가 있어도 한 번만 돈다).

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    private final TokenVerifier tokenVerifier;

    // 실제 필터 로직. 요청이 들어올 때마다 이 메서드가 호출된다.
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String header = request.getHeader(HEADER);

        // "Authorization: Bearer <토큰>" 형태의 헤더가 있을 때만 로그인 시도를 한다.
        // 헤더가 아예 없으면(예: /api/health 호출) 그냥 통과시키고, 나중에 SecurityConfig가
        // "이 경로는 인증 없이도 되는지"를 판단한다.
        if (header != null && header.startsWith(PREFIX)) {
            String idToken = header.substring(PREFIX.length());
            try {
                String uid = tokenVerifier.verifyAndGetUid(idToken);
                // SecurityContextHolder는 "지금 이 요청을 처리 중인 스레드에서, 누가 로그인했는지"를
                // 담아두는 저장소다. 여기에 인증 정보를 넣어두면, 이후 컨트롤러에서
                // SecurityContextHolder.getContext().getAuthentication().getName()으로 uid를 꺼내 쓸 수 있다.
                // principal 자리에 uid 문자열을 그대로 넣었기 때문에 getName()이 바로 uid를 반환한다.
                var authentication = new UsernamePasswordAuthenticationToken(uid, null, List.of());
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (TokenVerifier.InvalidTokenException e) {
                // 토큰이 가짜/만료됐으면 여기서 401을 직접 응답하지 않는다.
                // 대신 로그인 정보를 비워둔 채로 그냥 다음 필터로 넘기고, 최종적으로
                // SecurityConfig의 authenticated() 규칙과 HttpStatusEntryPoint가 401을 응답하게 맡긴다.
                // 이렇게 하면 "거절 응답을 만드는 코드"가 한 곳(스프링 시큐리티)에만 있게 된다.
                log.debug("토큰 검증 실패: {}", e.getMessage());
                SecurityContextHolder.clearContext();
            }
        }

        // 다음 필터(또는 최종적으로 컨트롤러)로 요청을 넘긴다. 이 호출을 안 하면 요청이 여기서 멈춰버린다.
        chain.doFilter(request, response);
    }
}
