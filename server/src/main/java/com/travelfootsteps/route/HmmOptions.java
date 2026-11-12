package com.travelfootsteps.route;

import jakarta.validation.constraints.Positive;

// hmm_steps의 조정값(설계 6-3). 요청에서 빠진 값은 아래 기본값을 쓴다. R6가 예비용 세션으로 β와 σ 하한을 정할 때
// 서버를 다시 빌드하지 않고 요청마다 바꿔 볼 수 있게 요청 값으로 받는다.
//  - betaM     : 전이 확률 exp(-|도로 경로거리 - 걸은 거리| / β)의 β(m)
//  - sigmaMinM : 방사 확률 가우시안의 σ 하한(m). σ = max(점 정확도, 하한)
//  - strideM   : 걸은 거리 = 걸음 수 × 보폭
//  - useSteps  : false면 걸은 거리 대신 두 점의 직선거리(Newson & Krumm 원래 식, 절제 실험)
// 아래 @Positive는 Bean Validation 애너테이션으로, 값이 있다면 0보다 커야 한다는 규칙이다(null은 통과하고 기본값이
// 채워진다). 0이나 음수 β·σ·보폭은 0으로 나누거나 확률 식이 깨지므로 막는다. 이 규칙은 컨트롤러가 요청 본문을 받을 때
// 검사되는데, ReconstructRequest에서 hmm 필드에 @Valid를 붙였기 때문에 안쪽 record까지 내려가 적용된다. @Valid가 없으면
// 이 애너테이션은 있어도 검사되지 않는다.
public record HmmOptions(
        @Positive Double betaM,
        @Positive Double sigmaMinM,
        @Positive Double strideM,
        Boolean useSteps
) {
    // 조정 전 기본값. β 10m는 OSRM 자체 맵 매칭의 기본값(MATCHING_BETA)과 같아 osrm_match_radius와 같은 β로
    // 견줄 수 있다. σ 하한 5m는 설계 6-3과 OSRM 기본 GPS 정밀도다. 둘 다 R6에서 예비용 세션으로 다시 정한다.
    static final double DEFAULT_BETA_M = 10.0;
    static final double DEFAULT_SIGMA_MIN_M = 5.0;
    static final double DEFAULT_STRIDE_M = 0.75;

    static final HmmOptions DEFAULTS =
            new HmmOptions(DEFAULT_BETA_M, DEFAULT_SIGMA_MIN_M, DEFAULT_STRIDE_M, true);

    /** 빠진 값을 기본값으로 채운다. options가 null이면 기본값 전체다. */
    static HmmOptions orDefaults(HmmOptions options) {
        if (options == null) return DEFAULTS;
        return new HmmOptions(
                options.betaM() != null ? options.betaM() : DEFAULT_BETA_M,
                options.sigmaMinM() != null ? options.sigmaMinM() : DEFAULT_SIGMA_MIN_M,
                options.strideM() != null ? options.strideM() : DEFAULT_STRIDE_M,
                options.useSteps() != null ? options.useSteps() : Boolean.TRUE);
    }
}
