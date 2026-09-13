package com.travelfootsteps.translate;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// @RestController: 이 클래스의 메서드가 리턴하는 객체를 JSON으로 직렬화해 HTTP 응답 바디에
// 그대로 싣는다는 뜻이다(뷰 템플릿을 렌더링하지 않는다).
// @RequestMapping("/api/translate"): 이 컨트롤러의 모든 메서드는 "/api/translate"로 시작하는
// 경로에만 매핑된다.
//
// 이 컨트롤러는 아주 얇다 — Google Cloud Translation API 키를 앱(APK)에 넣지 않기 위한
// "프록시"이기 때문이다. APK는 디컴파일될 수 있어서, 키를 앱 안에 두면 그대로 유출된다.
// 그래서 앱은 이 서버 엔드포인트만 호출하고, 실제 Google 호출과 키 관리는 서버(그리고 그 중에서도
// TranslationClient 구현체 하나)만 안다. 컨트롤러 자신은 TranslationClient 인터페이스에만
// 의존하므로, 번역 엔진이 무엇인지(Google NMT인지 나중에 LLM인지)조차 알 필요가 없다.
@RestController
@RequestMapping("/api/translate")
@RequiredArgsConstructor // Lombok: final 필드(translationClient)를 받는 생성자를 자동 생성한다.
public class TranslateController {

    private final TranslationClient translationClient;

    // @Valid: TranslateRequest에 붙은 @NotBlank 제약을 여기서 실제로 검사하게 만든다.
    // @RequestBody: HTTP 요청 바디(JSON)를 TranslateRequest 객체로 역직렬화한다.
    @PostMapping
    public TranslateResponse translate(@Valid @RequestBody TranslateRequest request) {
        TranslationResult result = translationClient.translate(
                request.text(), request.targetLanguage(), request.sourceLanguage());
        return TranslateResponse.from(result);
    }
}
