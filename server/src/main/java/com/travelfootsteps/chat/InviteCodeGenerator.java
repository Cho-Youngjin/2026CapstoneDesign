package com.travelfootsteps.chat;

import org.springframework.stereotype.Component;

import java.security.SecureRandom;

/**
 * 그룹 채팅방의 6자리 초대 코드를 만든다 (Plan D "데이터 모델 — 초대 코드").
 *
 * <p>사람이 보고 따라 입력하는 값이므로 헷갈리는 글자(숫자 0·1, 대문자 O·I·L)를 뺀
 * 31자만 쓴다. 31^6 ≈ 8.9억 가지라 무작위로 찍어서 남의 방에 들어갈 확률은 무시할 만하다.
 *
 * <p>{@link java.util.Random}이 아니라 {@link SecureRandom}을 쓰는 이유: 초대 코드는 방에
 * 들어가는 유일한 열쇠다. {@code Random}은 출력 몇 개로 다음 값을 예측할 수 있어, 코드 하나를
 * 받은 사람이 다른 방의 코드를 추측할 여지가 생긴다.
 *
 * <p>코드가 이미 쓰이고 있는지는 여기서 확인하지 않는다 — DB의 UNIQUE 제약이 판정하고,
 * 충돌 시 다시 뽑는 것은 호출부(RoomService)의 책임이다.
 */
@Component
public class InviteCodeGenerator {

    static final int LENGTH = 6;

    /** 대문자 23자(O·I·L 제외) + 숫자 8자(0·1 제외) = 31자. */
    static final String ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    // SecureRandom은 스레드 안전하므로 빈 하나에서 공유해도 된다.
    private final SecureRandom random = new SecureRandom();

    public String generate() {
        StringBuilder code = new StringBuilder(LENGTH);
        for (int i = 0; i < LENGTH; i++) {
            code.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        }
        return code.toString();
    }
}
