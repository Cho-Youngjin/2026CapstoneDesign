package com.travelfootsteps.chat;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 초대 코드 생성 규칙 (Plan D "데이터 모델 — 초대 코드").
 * <ul>
 *     <li>6자리</li>
 *     <li>대문자 + 숫자 중 헷갈리는 글자(0, O, 1, I, L)를 뺀 31자만 사용</li>
 *     <li>SecureRandom으로 생성 — 약 8.9억 가지</li>
 * </ul>
 * DB 없이 도는 순수 단위 테스트다.
 */
class InviteCodeGeneratorTest {

    private static final int SAMPLES = 10_000;

    /**
     * 허용 문자 31자 = 대문자 23자(A-H, J, K, M, N, P-Z — O·I·L 제외) + 숫자 8자(2-9 — 0·1 제외).
     * 이 정규식 하나로 "길이 6"과 "허용 문자만"을 함께 검사한다.
     */
    private static final String VALID_CODE = "[A-HJKMNP-Z2-9]{6}";

    private final InviteCodeGenerator generator = new InviteCodeGenerator();

    @Test
    void 코드는_6자리다() {
        String code = generator.generate();

        assertThat(code).hasSize(6);
    }

    @Test
    void 허용된_문자만_사용한다() {
        List<String> codes = generate(SAMPLES);

        // allSatisfy는 실패 시 "어떤 코드가" 규칙을 어겼는지 메시지에 보여준다.
        // for문 안의 assertTrue는 첫 실패에서 멈추고 무엇이 틀렸는지 알려주지 않는다.
        assertThat(codes).allSatisfy(code -> assertThat(code).matches(VALID_CODE));
    }

    @Test
    void 매번_다른_코드가_나온다() {
        Set<String> unique = Set.copyOf(generate(SAMPLES));

        // 8.9억 가지 중 1만 개라 충돌은 거의 없지만, "충돌 0개"로 단정하면 드물게 깨지는
        // 불안정한 테스트가 되므로 여유를 둔다(기대 충돌 수는 약 0.06개).
        assertThat(unique).hasSizeGreaterThan(9_990);
    }

    private List<String> generate(int count) {
        return IntStream.range(0, count)
                .mapToObj(i -> generator.generate())
                .collect(Collectors.toList());
    }
}
