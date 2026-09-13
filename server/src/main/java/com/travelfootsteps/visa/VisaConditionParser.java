package com.travelfootsteps.visa;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 외교부 입국허가요건 API의 자연어 필드(visa_cn, evidence text, remark 등)를
 * {@link ParsedVisaCondition}으로 정규화하는 순수 파서.
 *
 * <p>이 클래스는 Spring 빈이 아니다 — HTTP 호출도, DB 접근도 하지 않는 순수 로직이라
 * 스프링 없이도(즉, 실제 API 응답을 받아오지 않고도) 바로 단위 테스트로 검증할 수 있다.
 * Task 3의 {@code VisaRequirementCollector}가 이 클래스를 직접 {@code new}로 생성해 호출한다.
 *
 * <p><b>설계 원칙: 확신이 없으면 null을 반환한다.</b> 잘못된 숫자로 "무비자 45일"이라고
 * 잘못 안내하는 것이, "영사관 확인 필요"라고 보수적으로 안내하는 것보다 훨씬 나쁘다
 * (스펙 §5 "검증되지 않은 데이터로 잘못된 비자 안내를 하지 않는 것이 원칙"). 그래서 서로
 * 다른 숫자가 동시에 검출되면 모순(ambiguous)으로 보고 null을 반환하며, 같은 숫자가
 * 반복 검출되는 것은 모순이 아니므로 그대로 반환한다.
 *
 * <p>{@code visaFreeDays}와 {@code passportValidityMonths}의 null 의미가 서로 다르다는 점은
 * {@link ParsedVisaCondition}의 클래스 문서를 참고한다.
 *
 * <p>패턴은 실제 API 데이터를 확보하는 대로 계속 추가해야 한다. 새로운 문구 변형을
 * 발견하면 패턴을 추가하되, 기존 패턴은 제거하지 않는다 — 실제 데이터에 어떤 변형이
 * 더 있을지 알 수 없으므로 패턴은 계속 누적하는 것이 안전하다.
 */
public class VisaConditionParser {

    // "90일", "30일간" 처럼 숫자 뒤에 "일"(선택적으로 "간")이 붙는 무비자 체류일수 표기.
    // "간"을 옵션으로 둔 이유: "체류 가능"류 문구는 "일"로 끝나고, "협정에 의해 ~일간 체류"류
    // 문구는 "일간"으로 끝나기 때문에 두 변형을 하나의 패턴으로 함께 잡는다.
    private static final List<Pattern> DAY_PATTERNS = List.of(
            Pattern.compile("(\\d+)\\s*일간?")
    );

    // "체류기간 6개월"처럼 개월 단위로 체류 가능 기간을 표기하는 경우. 무비자 일수 필드는
    // "일" 단위가 기본이므로, 개월 단위로 검출된 값은 30을 곱해 일 단위로 환산한다(스펙의
    // 개월→일 환산 규칙, 실제 달력상의 월별 일수 차이는 무시하는 근사치임을 주석으로 남긴다).
    // 두 패턴은 "체류(기간)? ... N개월"과 "N개월(간)? 체류"라는 서로 다른 어순을 모두 잡기 위함이다.
    private static final List<Pattern> MONTH_AS_STAY_PATTERNS = List.of(
            Pattern.compile("체류\\s*(?:기간)?\\s*[:：]?\\s*(\\d+)\\s*개월"),
            Pattern.compile("(\\d+)\\s*개월\\s*(?:간)?\\s*체류")
    );

    // 여권 잔여유효기간 요건 표기. "여권 유효기간/잔여유효기간/잔여기간이 N개월 이상 남아야/필요"
    // 류의 문구를 잡는다. [^0-9]{0,10}은 "이/가 입국일로부터", "잔여유효기간이" 같은 조사·수식어가
    // 숫자 앞에 최대 10글자까지 끼어들 수 있음을 허용하되, 다른 숫자가 먼저 등장하면(예: 다른 문장의
    // 숫자) 오매칭을 막기 위해 범위를 제한한 것이다.
    // pattern1: "여권"이 반드시 앞에 와야 하는 가장 일반적인 형태.
    // pattern2: "여권"이라는 단어 없이 "유효기간/잔여기간 ... N개월 ... 이상/남아"만으로도 잡되,
    //           "이상"/"남아"가 뒤따르는 문맥으로 한정해 오탐을 줄인다.
    private static final List<Pattern> PASSPORT_VALIDITY_PATTERNS = List.of(
            Pattern.compile("여권\\s*(?:유효기간|잔여\\s*유효기간|잔여기간)[^0-9]{0,10}(\\d+)\\s*개월"),
            Pattern.compile("(?:유효기간|잔여기간)[^0-9]{0,10}(\\d+)\\s*개월[^가-힣]{0,10}(?:이상|남아)")
    );

    /**
     * 외교부 API의 원본 필드를 정규화된 {@link ParsedVisaCondition}으로 변환한다.
     *
     * <p><b>2026-09-13 실 API 검증 결과, visaYn 파라미터는 제거했다</b> — 실제 data.go.kr
     * EntranceVisaService2를 국가 필터 없이 전수 조회(190개국)한 결과 gnrl_pspt_visa_yn은
     * 190/190 전부 "Y"였다(비자가 반드시 필요한 아프가니스탄·소말리아·시리아·인도까지 포함).
     * 즉 이 필드는 "비자 필요 여부"라는 이름과 달리 실제로는 아무 신호도 담고 있지 않다.
     * 진짜 신호는 gnrl_pspt_visa_cn에 있다 — 무비자 불가 국가는 정확히 "X" 리터럴이고,
     * 무비자 가능 국가는 일수를 나타내는 자유 텍스트다(예: "45일").
     *
     * <p><b>2026-09-13 재검토로 추가된 "X" 우선 분기</b>: "X"는 "몰라서 없음"이 아니라
     * "무비자 불가"라는 확정 신호이므로, evidenceText를 뒤져 일수를 뽑기 전에 먼저 분기해서
     * visaRequired=true, visaFreeDays=0(파싱 실패의 null과 구분되는 "확정된 0일")으로 즉시
     * 확정한다. 이 분기가 없으면 두 가지 문제가 생긴다: (1)
     * {@code VisaJudgementService.determineVerdict()}의 최우선 규칙이 visaFreeDays==null이면
     * 무조건 UNVERIFIED로 처리하므로, "X"가 계속 null을 반환하는 한 VISA_REQUIRED 분기 자체가
     * 영원히 도달 불가능해진다(인도처럼 실제 비자가 필요한 나라도 UNVERIFIED로 잘못 나온다).
     * (2) evidenceText에 우연히 숫자+"일" 패턴이 섞여 있으면(현재 65개 X 국가 중 0개지만,
     * 데이터가 갱신되면 생길 수 있는 잠재 위험) visaFreeDays가 non-null이 되어 무비자 OK로
     * 오판정될 수 있다. "X"를 최우선으로 분기하면 두 문제 모두 원천 차단된다.
     *
     * @param visaCn 비자 조건에 대한 자연어 설명 (예: "45일", 또는 무비자 불가 시 "X").
     * @param evidenceText 근거 문구(있으면). visaCn과 함께 무비자 일수 후보를 찾는 데 쓰인다.
     * @param remark 비고란 자연어 텍스트. 여권 잔여유효기간 요건을 찾는 데 쓰인다.
     * @return 파싱 결과.
     */
    public ParsedVisaCondition parse(String visaCn, String evidenceText, String remark) {
        Integer passportValidityMonths = extractPassportValidityMonths(join(visaCn, remark, evidenceText));

        if ("X".equalsIgnoreCase(visaCn == null ? "" : visaCn.trim())) {
            // 확정 신호: 무비자 입국 불가. 0은 "확정된 0일"이고 null("몰라서 없음")과 구분된다 —
            // evidenceText를 뒤져 일수 후보를 찾는 아래 로직 자체를 아예 타지 않는다.
            return new ParsedVisaCondition(true, 0, passportValidityMonths);
        }

        Integer visaFreeDays = extractFreeDays(join(visaCn, evidenceText));
        return new ParsedVisaCondition(visaFreeDays == null, visaFreeDays, passportValidityMonths);
    }

    private Integer extractFreeDays(String text) {
        if (text.isBlank()) {
            return null;
        }

        List<Integer> dayMatches = findAll(DAY_PATTERNS, text);
        List<Integer> monthMatches = findAll(MONTH_AS_STAY_PATTERNS, text);

        List<Integer> normalizedDays = new ArrayList<>(dayMatches);
        for (Integer months : monthMatches) {
            normalizedDays.add(months * 30);
        }

        return uniqueOrNull(normalizedDays);
    }

    private Integer extractPassportValidityMonths(String text) {
        if (text.isBlank()) {
            return null;
        }
        List<Integer> matches = findAll(PASSPORT_VALIDITY_PATTERNS, text);
        return uniqueOrNull(matches);
    }

    /**
     * 후보 숫자들이 전부 같은 값이면 그 값을, 하나도 없으면(못 찾음) null을,
     * 서로 다른 값이 섞여 있으면(모순 = ambiguous) 안전하게 null을 반환한다.
     */
    private Integer uniqueOrNull(List<Integer> values) {
        if (values.isEmpty()) {
            return null;
        }
        long distinctCount = values.stream().distinct().count();
        if (distinctCount > 1) {
            return null;
        }
        return values.get(0);
    }

    private List<Integer> findAll(List<Pattern> patterns, String text) {
        List<Integer> results = new ArrayList<>();
        for (Pattern pattern : patterns) {
            Matcher matcher = pattern.matcher(text);
            while (matcher.find()) {
                results.add(Integer.parseInt(matcher.group(1)));
            }
        }
        return results;
    }

    /** null/blank 항목은 건너뛰고 나머지를 공백으로 이어붙여 하나의 검색 대상 텍스트를 만든다. */
    private String join(String... parts) {
        StringBuilder sb = new StringBuilder();
        for (String part : parts) {
            if (part != null && !part.isBlank()) {
                sb.append(part).append(' ');
            }
        }
        return sb.toString().trim();
    }
}
