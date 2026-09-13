package com.travelfootsteps.visa;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

class VisaConditionParserTest {

    private final VisaConditionParser parser = new VisaConditionParser();

    @Test
    void 실제_API_샘플_베트남_45일_무비자() {
        // 실제 라이브 API 응답(2026-09-13 검증): gnrl_pspt_visa_yn=Y(무의미), gnrl_pspt_visa_cn="45일"
        ParsedVisaCondition result = parser.parse("45일",
                "외교관여권 소지자 : 협정 \n 관용여권 소지자 : 협정 \n 일반여권 소지자 : 일방", "");

        assertThat(result.visaRequired()).isFalse();
        assertThat(result.visaFreeDays()).isEqualTo(45);
    }

    @Test
    void 실제_API_샘플_인도_X_비자필요() {
        // 실제 라이브 API 응답(2026-09-13 검증): gnrl_pspt_visa_yn=Y(무의미), gnrl_pspt_visa_cn="X"
        ParsedVisaCondition result = parser.parse("X",
                "외교관여권 소지자 : 협정 \n 관용여권 소지자 : 협정", "");

        assertThat(result.visaRequired()).isTrue();
        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void 스펙에_인용된_실제_문구_관광_목적_90일_무비자() {
        // docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md §4에 인용된 실제 문구.
        ParsedVisaCondition result = parser.parse("관광 목적 90일 무비자", null, null);

        assertThat(result.visaRequired()).isFalse();
        assertThat(result.visaFreeDays()).isEqualTo(90);
        assertThat(result.passportValidityMonths()).isNull();
    }

    @Test
    void 무비자_일수를_뽑아내지_못하면_비자required_이고_freeDays는_null이다() {
        // "X" 리터럴처럼 일수 패턴이 전혀 없는 문구는 파싱 실패로 취급해 비자 필요로 간주한다.
        // 예전에는 visaFreeDays를 강제로 0으로 채웠지만(별도 visaYn 파라미터가 있던 시절의
        // NPE 회피용 분기), 그 분기는 더 이상 존재하지 않는다 — null은 이 클래스 전체에서
        // "몰라서 없음"을 뜻하므로, 비자가 필요할 때도 그 의미를 그대로 유지한다.
        ParsedVisaCondition result = parser.parse("X", null, null);

        assertThat(result.visaRequired()).isTrue();
        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void 협정에_의한_무비자_문구도_일수를_추출한다() {
        ParsedVisaCondition result = parser.parse("사증면제협정에 의해 30일간 체류 가능", null, null);

        assertThat(result.visaFreeDays()).isEqualTo(30);
    }

    @Test
    void 개월_단위_표기는_30일_기준으로_환산한다() {
        ParsedVisaCondition result = parser.parse("무비자 입국 가능 (체류기간 6개월)", null, null);

        assertThat(result.visaFreeDays()).isEqualTo(180);
    }

    @Test
    void 숫자를_찾을_수_없으면_visaFreeDays는_null이다() {
        ParsedVisaCondition result = parser.parse("자료없음", null, null);

        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void 서로_다른_숫자가_모순되면_ambiguous로_null_처리한다() {
        ParsedVisaCondition result = parser.parse(
                "일반적으로 90일 무비자이나 일부 지역은 30일만 허용", null, null);

        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void 같은_숫자가_반복되면_ambiguous가_아니다() {
        ParsedVisaCondition result = parser.parse(
                "관광 목적 90일 무비자. 상용 목적도 동일하게 90일 적용", null, null);

        assertThat(result.visaFreeDays()).isEqualTo(90);
    }

    @ParameterizedTest
    @CsvSource({
            "여권 유효기간이 입국일로부터 6개월 이상 남아야 함, 6",
            "여권 잔여유효기간 3개월 이상 요구, 3",
            "출국일 기준 여권 유효기간 1개월 이상 필요, 1",
    })
    void 여권_잔여유효기간_문구에서_개월수를_추출한다(String remark, int expectedMonths) {
        ParsedVisaCondition result = parser.parse("관광 목적 90일 무비자", null, remark);

        assertThat(result.passportValidityMonths()).isEqualTo(expectedMonths);
    }

    @Test
    void 여권_요건_언급이_없으면_null이다_요건없음으로_간주() {
        ParsedVisaCondition result = parser.parse("관광 목적 90일 무비자", null, "특이사항 없음");

        assertThat(result.passportValidityMonths()).isNull();
    }

    @Test
    void evidenceText에서도_일수를_찾는다() {
        ParsedVisaCondition result = parser.parse("무비자", "협정에 의해 60일간 체류 허용", null);

        assertThat(result.visaFreeDays()).isEqualTo(60);
    }
}
