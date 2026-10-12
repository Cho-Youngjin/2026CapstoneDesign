package com.travelfootsteps.exchangerate;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * 서버를 띄울 때 환율 캐시가 비어 있으면 최근 영업일 2개를 거슬러 올라가 채운다(설계 §4.4).
 *
 * <p>왜 필요한가 — 스케줄 배치는 영업일 11:05 이후에만 돈다. 서버를 처음 띄운 날이 주말이거나
 * 11시 이전이면, 다음 영업일 오전까지 환율이 하나도 없어 지갑 배너가 비고 알림도 동작하지 않는다.
 *
 * <p>@Component + ApplicationRunner: 스프링 부트가 기동을 마친 뒤(내장 웹서버가 요청을 받을 수 있게 된 뒤)
 * run()을 자동으로 호출한다. 우리가 직접 부르는 코드는 어디에도 없다.
 * <p>@Profile("!test"): 활성 프로필이 test가 아닐 때만 이 빈을 만든다. @SpringBootTest 테스트가 기동하면서
 * 실제 수출입은행·open.er-api.com을 호출하는 일을 막는다.
 * <p>보정 실행이 실패해도 서버 기동은 계속된다 — 예외를 잡아 로그만 남기고, 다음 스케줄에서 다시 받는다.
 */
@Slf4j
@Component
@Profile("!test")
@RequiredArgsConstructor
public class ExchangeRateStartupBackfill implements ApplicationRunner {

    private final ExchangeRateBatchScheduler scheduler;

    @Override
    public void run(ApplicationArguments args) {
        try {
            scheduler.backfillIfNeeded(LocalDate.now(ExchangeRateBatchScheduler.KST));
        } catch (Exception e) {
            log.error("기동 시 환율 보정 실패 — 다음 스케줄에서 다시 시도한다", e);
        }
    }
}
