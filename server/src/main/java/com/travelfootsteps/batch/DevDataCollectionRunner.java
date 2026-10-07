package com.travelfootsteps.batch;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * 로컬 개발·실기기 테스트용: 서버를 띄울 때 공공데이터 수집을 즉시 한 번 돌린다.
 *
 * <p>왜 필요한가 — {@link DailyDataCollectionScheduler}는 매일 03:00(KST) cron에만 돌고
 * 수동 트리거 엔드포인트가 없다. 그래서 DB가 빈 상태로 서버를 처음 띄우면
 * {@code visa_requirement}/{@code travel_alert}/{@code embassy} 테이블이 전부 비어 있어,
 * 비자 판정은 모든 국가가 "영사관 확인 필요"(UNVERIFIED)로 나오고 주변정보 탭의 경보 배지·
 * 공관 카드도 빈 상태가 된다. 새벽 3시까지 기다리지 않고 지금 기기에서 확인하기 위한 장치다.
 */
// @Component: 스프링 빈으로 등록한다. ApplicationRunner 구현 빈은 스프링 부트가 알아서 찾아
// 애플리케이션 기동이 끝난 뒤 run()을 호출해 준다 — 우리가 직접 부르는 코드는 어디에도 없다.
//
// @Profile("dev"): 활성 프로필이 "dev"일 때만 이 빈을 등록한다. 즉 평소(프로필 없이 실행,
// 테스트, 배포)에는 아예 빈으로 만들어지지 않아 기동 시 수집이 돌지 않는다. 운영 서버가
// 재시작될 때마다 외부 API 쿼터를 태우는 일을 막기 위해 의도적으로 프로필 뒤에 둔다.
//   실행: ./gradlew bootRun --args='--spring.profiles.active=dev'
//
// @RequiredArgsConstructor(Lombok): final 필드를 받는 생성자를 자동 생성한다 — 스프링이
// 그 생성자로 DailyDataCollectionScheduler 빈을 주입한다.
//
// 참고로 ApplicationRunner.run()은 내장 웹서버가 이미 포트를 열어 요청을 받을 수 있게 된
// 뒤에 실행된다. 따라서 수집이 몇 분 걸려도 서버 자체는 그 동안 정상 응답한다 — 다만 수집이
// 끝나기 전에는 비자/경보/공관 데이터가 일부만 채워져 있으니, 로그에 "일일 공공데이터 수집
// 종료"가 찍힌 뒤에 기기에서 확인하는 것이 좋다.
@Slf4j
@Component
@Profile("dev")
@RequiredArgsConstructor
public class DevDataCollectionRunner implements ApplicationRunner {

    private final DailyDataCollectionScheduler scheduler;

    @Override
    public void run(ApplicationArguments args) {
        log.info("dev 프로필 — 기동 직후 공공데이터 수집을 한 번 실행한다 "
                + "(API 키가 비어 있으면 각 수집기가 조용히 실패하고 넘어간다)");
        scheduler.runDaily();
    }
}
