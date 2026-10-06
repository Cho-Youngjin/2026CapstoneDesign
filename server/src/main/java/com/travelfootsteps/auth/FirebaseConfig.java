package com.travelfootsteps.auth;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.FirebaseAuth;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.Resource;

import java.io.IOException;
import java.io.InputStream;

// @Configuration: 이 클래스는 "설정 클래스"이고, 안에 있는 @Bean 메서드들이 리턴하는 객체를
// 스프링 컨테이너가 관리하는 빈으로 등록한다. 다른 클래스에서 생성자로 FirebaseApp/FirebaseAuth를
// 요청하면(의존성 주입) 스프링이 여기서 만든 인스턴스를 넣어준다.
//
// @Profile("!test"): "test 프로필이 아닐 때만" 이 설정을 활성화한다는 뜻이다. test 프로필은
// application.yml이 아니라 테스트 클래스마다 @ActiveProfiles("test")를 붙여서 켠다
// (CountryControllerTest, HealthControllerTest 참고). 이 클래스가 실제
// firebase-service-account.json 파일(진짜 비밀키)이 있어야만 동작하는데, 테스트 환경에는
// 그 파일이 없으므로(팀원 각자 로컬에만 둠), 프로필로 아예 꺼버려서
// "파일이 없어서 테스트가 실패하는" 상황을 막는다.
@Configuration
@Profile("!test")
public class FirebaseConfig {

    // application.yml의 firebase.service-account-path 값을 그대로 주입받는다.
    // @Value는 설정 파일(application.yml)의 값을 필드에 꽂아주는 애너테이션이다.
    @Value("${firebase.service-account-path}")
    private Resource serviceAccount;

    // Firebase Admin SDK를 초기화하는 빈. 서버가 Firebase에 "나는 이 프로젝트의 관리자다"라고
    // 증명할 때 이 서비스 계정 키 파일(비공개 키)을 사용한다 — 이 키가 있어야 다른 사람이 만든
    // ID Token이 진짜인지 검증할 수 있다.
    @Bean
    public FirebaseApp firebaseApp() throws IOException {
        // FirebaseApp은 프로세스당 한 번만 초기화해야 한다(싱글톤 패턴 — "이미 인스턴스가 있으면
        // 새로 안 만들고 기존 걸 재사용한다"가 싱글톤의 핵심이다). 스프링이 테스트 등에서 컨텍스트를
        // 다시 띄울 때 중복 초기화 예외가 나지 않도록, 이미 초기화돼 있으면 기존 인스턴스를 재사용한다.
        // 참고로 스프링 빈 자체도 기본 스코프가 싱글톤이라 컨테이너 안에서는 한 번만 만들어지는데,
        // 여기서 굳이 수동 체크를 하는 이유는 Firebase SDK가 "같은 프로세스에서 두 번 초기화하면
        // 예외를 던진다"는 자체 정책을 갖고 있어, 스프링 컨텍스트가 여러 번 재시작될 때(테스트 등)
        // 그 SDK 레벨 중복 초기화까지 막기 위함이다.
        if (!FirebaseApp.getApps().isEmpty()) {
            return FirebaseApp.getInstance();
        }
        try (InputStream in = serviceAccount.getInputStream()) {
            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(in))
                    .build();
            return FirebaseApp.initializeApp(options);
        }
    }

    // 위에서 만든 FirebaseApp을 받아서(스프링이 자동으로 연결해준다), 실제로 ID Token을 검증할 때
    // 쓰는 FirebaseAuth 객체를 빈으로 등록한다. FirebaseTokenVerifier가 이 빈을 주입받아 사용한다.
    @Bean
    public FirebaseAuth firebaseAuth(FirebaseApp app) {
        return FirebaseAuth.getInstance(app);
    }
}
