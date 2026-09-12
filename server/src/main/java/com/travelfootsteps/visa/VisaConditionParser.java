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
     * @param visaYn "Y"(비자 필요) / "N"(무비자) 등 비자 필요 여부 원본 코드.
     * @param visaCn 비자 조건에 대한 자연어 설명 (예: "관광 목적 90일 무비자").
     * @param evidenceText 근거 문구(있으면). visaCn과 함께 무비자 일수 후보를 찾는 데 쓰인다.
     * @param remark 비고란 자연어 텍스트. 여권 잔여유효기간 요건을 찾는 데 쓰인다.
     * @return 파싱 결과. visaYn == "Y"이면 visaFreeDays는 항상 0이다(비자가 필요하므로
     *         "무비자 일수"라는 개념 자체가 해당 없음 = 0일).
     */
    public ParsedVisaCondition parse(String visaYn, String visaCn, String evidenceText, String remark) {
        boolean visaRequired = "Y".equalsIgnoreCase(trim(visaYn));

        // 비자가 필요한 경우 "무비자 일수"는 개념적으로 0이다 — 파싱 실패(null)가 아니라
        // 확정된 값이므로 굳이 텍스트에서 숫자를 찾을 필요가 없다.
        //
        // 주의: `visaRequired ? 0 : extractFreeDays(...)` 처럼 삼항 연산자로 쓰면 안 된다.
        // 두 분기의 타입이 각각 int(0)와 Integer(extractFreeDays의 반환값)로 다르면, 자바
        // 삼항 연산자는 이항 수치 승격(binary numeric promotion) 규칙에 따라 Integer 쪽을
        // int로 언박싱해 버린다. extractFreeDays(...)가 (의도한 대로) null을 반환하면 이
        // 언박싱 과정에서 NullPointerException이 터진다 — if/else로 풀어써야 안전하다.
        Integer visaFreeDays;
        if (visaRequired) {
            visaFreeDays = 0;
        } else {
            visaFreeDays = extractFreeDays(join(visaCn, evidenceText));
        }

        // 여권 잔여유효기간은 visaYn과 무관하게(비자가 필요하든 무비자든) 언급 여부를 확인한다.
        Integer passportValidityMonths = extractPassportValidityMonths(join(visaCn, remark, evidenceText));

        return new ParsedVisaCondition(visaRequired, visaFreeDays, passportValidityMonths);
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

    private String trim(String s) {
        return s == null ? "" : s.trim();
    }
}
