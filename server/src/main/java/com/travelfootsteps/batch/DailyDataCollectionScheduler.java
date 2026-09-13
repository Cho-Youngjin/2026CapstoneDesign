package com.travelfootsteps.batch;

import com.travelfootsteps.alert.TravelAlertCollector;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.embassy.EmbassyCollector;
import com.travelfootsteps.visa.VisaRequirementCollector;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

// @Slf4j(Lombok): 이 클래스 전용 로거(log)를 자동 생성한다.
// @Component: 스프링 빈으로 등록한다 — @Scheduled 메서드가 실제로 주기 실행되려면 이 클래스가
// 스프링 컨테이너에 등록된 빈이어야 하고(그래야 스케줄러 인프라가 찾아서 관리할 수 있다),
// 스프링 부트가 @EnableScheduling(또는 이에 준하는 자동 설정)으로 스케줄링 인프라를 켜둔 상태여야 한다.
// @RequiredArgsConstructor(Lombok): final 필드 4개(countryRepository + 수집기 3종)를 받는
// 생성자를 자동 생성한다 — 스프링이 그 생성자를 보고 의존성을 주입한다.
@Slf4j
@Component
@RequiredArgsConstructor
public class DailyDataCollectionScheduler {

    private final CountryRepository countryRepository;
    private final VisaRequirementCollector visaRequirementCollector;
    private final TravelAlertCollector travelAlertCollector;
    private final EmbassyCollector embassyCollector;

    /**
     * 전 국가(country 테이블의 전체 행, Tier A/B 구분 없이)를 순회하며 비자·여행경보·재외공관
     * 세 수집기를 순서대로 한 번씩 돌린다. Tier A(수기 검증 완료) 국가의 판정 필드 보존은
     * VisaRequirementCollector 내부에서 verified 플래그로 처리하므로, 이 스케줄러는 Tier를
     * 신경 쓰지 않고 모든 국가에 동일하게 세 수집기를 호출하기만 하면 된다.
     *
     * <p>{@code @Scheduled(cron = "0 0 3 * * *", zone = "Asia/Seoul")}: 매일 한국 시간(KST)
     * 03시 00분 00초에 스프링이 이 메서드를 자동 호출한다. cron 표현식은 왼쪽부터
     * "초 분 시 일 월 요일" 순서다 — "0 0 3 * * *"는 "초=0, 분=0, 시=3, 일/월/요일은 무관(*)"이라는
     * 뜻이라 매일 03:00:00에 실행된다. zone을 명시하지 않으면 서버 JVM의 기본 타임존을 쓰게 되어
     * 배포 환경에 따라 실행 시각이 달라질 수 있으므로 "Asia/Seoul"로 고정한다.
     *
     * <p>이 메서드는 public이라 테스트에서 스케줄과 무관하게 직접 호출해 검증할 수 있다 — 실제
     * 운영에서는 cron이 호출하고, 테스트에서는 사람(또는 테스트 코드)이 즉시 호출한다.
     *
     * <p>각 수집기의 {@code collectOne}은 이미 {@link com.travelfootsteps.externaldata.ExternalApiException}
     * (재시도를 다 소진한 뒤의 "예상된" 외부 API 실패)을 내부에서 잡아 조용히 반환한다. 하지만
     * 그 외의 "예상치 못한" 예외(예: 데이터 파싱 버그로 인한 NullPointerException, DB 제약
     * 위반 등)까지 수집기가 전부 막아준다고 가정할 수는 없다 — 그런 예외는 그대로 이 메서드까지
     * 전파되어, 잡아주지 않으면 국가 순회 for문 자체가 중단되어 뒤에 남은 국가들이 아예
     * 처리되지 못한다. 그래서 collectSafely()로 한 번 더 감싸 "이 나라, 이 수집기 하나의
     * 예상치 못한 실패가 나머지 국가 처리를 막지 않도록" 방어한다 — 수집기가 이미 처리하는
     * ExternalApiException 흡수 로직과 중복이 아니라, 그 로직이 놓칠 수 있는 사각지대를 메우는
     * 것이다.
     */
    @Scheduled(cron = "0 0 3 * * *", zone = "Asia/Seoul")
    public void runDaily() {
        var countries = countryRepository.findAll();
        log.info("일일 공공데이터 수집 시작: {}개국", countries.size());

        for (Country country : countries) {
            collectSafely(country, "visa", () -> visaRequirementCollector.collectOne(country));
            collectSafely(country, "alert", () -> travelAlertCollector.collectOne(country));
            collectSafely(country, "embassy", () -> embassyCollector.collectOne(country));
        }

        log.info("일일 공공데이터 수집 종료");
    }

    // 수집기 호출 하나를 감싸서, 예상치 못한 예외(RuntimeException 계열 전체)가 나도 로그만
    // 남기고 다음 수집기/다음 국가로 넘어가게 한다. Runnable로 받은 이유는 세 수집기
    // (visa/alert/embassy)의 collectOne 시그니처가 서로 달라서(반환 타입은 모두 void지만
    // 수집기 타입 자체가 다르다) 공통 인터페이스가 없기 때문 — 람다로 호출부에서 어떤
    // 수집기의 어떤 국가 호출인지를 그대로 캡처해서 넘긴다.
    private void collectSafely(Country country, String label, Runnable task) {
        try {
            task.run();
        } catch (Exception e) {
            log.error("{} 수집 중 예상치 못한 오류, 다음 국가로 진행: country={}", label, country.getIsoAlpha2(), e);
        }
    }
}
