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
        // "X"는 "몰라서 없음"이 아니라 "무비자 불가"라는 확정 신호이므로 visaFreeDays는
        // null(파싱 실패)이 아니라 0(확정된 0일)이어야 한다 — 2026-09-13 재검토 반영.
        ParsedVisaCondition result = parser.parse("X",
                "외교관여권 소지자 : 협정 \n 관용여권 소지자 : 협정", "");

        assertThat(result.visaRequired()).isTrue();
        assertThat(result.visaFreeDays()).isEqualTo(0);
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
    void 일수_패턴이_전혀_없는_문구는_파싱_실패로_비자required_이고_freeDays는_null이다() {
        // "X"가 아닌, 진짜로 알 수 없는 문구는 여전히 null(파싱 실패)로 남아야 한다 — "X"만
        // 확정 신호(0)로 특별 취급하고, 그 밖의 미확정 케이스의 null 의미는 그대로 유지한다.
        ParsedVisaCondition result = parser.parse("자료없음(비X)", null, null);

        assertThat(result.visaRequired()).isTrue();
        assertThat(result.visaFreeDays()).isNull();
    }

    @Test
    void X는_evidenceText에_숫자가_섞여있어도_무비자_오판정되지_않고_확정적으로_비자필요다() {
        // 2026-09-13 재검토에서 지적된 잠재 위험: "X" 국가의 evidenceText에 우연히 숫자+"일"
        // 패턴이 섞여 있으면(현재 실제 65개 X 국가 중 0개지만 데이터 갱신 시 생길 수 있는 위험)
        // extractFreeDays가 그 숫자를 주워서 visaRequired=false(무비자 OK)로 오판정될 수 있었다.
        // "X"를 evidenceText 탐색보다 먼저 분기하므로 이런 false-positive가 원천 차단되어야 한다.
        ParsedVisaCondition result = parser.parse("X", "과거 협정상 30일 체류가 언급된 적이 있으나 폐기됨", null);

        assertThat(result.visaRequired()).isTrue();
        assertThat(result.visaFreeDays()).isEqualTo(0);
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
