package com.travelfootsteps.support;

import com.travelfootsteps.translate.TranslationClient;
import com.travelfootsteps.translate.TranslationResult;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * TranslationClient의 test 프로필 전용 no-op 스텁. StubPlacesClient와 같은 이유 —
 * GoogleTranslateClient가 @Profile("!test")라 test 프로필에서 이 인터페이스의 빈이 아예
 * 없어지고, TranslateController를 컴포넌트 스캔하는 모든 @SpringBootTest가 이 빈 없이는
 * 컨텍스트를 못 띄운다. TranslateControllerTest 자신은 @WebMvcTest 슬라이스라 무관하다.
 */
@Component
@Profile("test")
public class StubTranslationClient implements TranslationClient {
    @Override
    public TranslationResult translate(String text, String targetLanguage, String sourceLanguage) {
        return new TranslationResult(text, sourceLanguage);
    }
}
