package com.travelfootsteps.visa;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.externaldata.ExternalApiException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Optional;

// @Component: 이 클래스를 스프링 빈으로 등록한다. Task 4의 스케줄러(아직 구현 전)가 이 빈을
// 주입받아, 국가 목록을 순회하며 국가 하나마다 collectOne()을 한 번씩 호출하게 될 것이다.
// @RequiredArgsConstructor(Lombok): 생성자 주입이 필요한 final 필드(client/repository)를 받는
// 생성자를 자동으로 만들어준다 — 스프링이 그 생성자를 보고 두 의존성을 주입한다. parser 필드는
// 아래에 설명하듯 스프링 빈이 아니라서 이 생성자에서 제외된다.
// @Slf4j(Lombok): 이 클래스 전용 로거(log)를 자동으로 만들어준다.
//
// 배치 흐름에서의 위치: (Task 4 스케줄러) -> VisaRequirementCollector.collectOne(country) ->
// EntranceVisaClient.fetch() -> DataGoKrHttpClient.getItems() -> data.go.kr 실제 HTTP 호출.
// 이 클래스가 "국가 하나에 대한 수집·판정·저장" 전체를 책임지는 단위이며, 스케줄러는 이 메서드를
// 반복 호출하기만 하면 된다 — 한 국가가 실패해도 이 메서드가 예외를 삼키므로 배치 전체는 계속된다.
@Slf4j
@Component
@RequiredArgsConstructor
public class VisaRequirementCollector {

    // 이 수집기가 다루는 것은 일반 여권(GENERAL)뿐이다. 관용/외교관 여권(OFFICIAL/DIPLOMATIC)은
    // 스키마가 미래를 위해 허용해둔 값일 뿐, 이 수집기 범위 밖이다.
    private static final String PASSPORT_TYPE_GENERAL = "GENERAL";

    private final EntranceVisaClient client;
    private final VisaRequirementRepository repository;

    // 주의: VisaConditionParser는 (Task 2의 설계상) 스프링 빈이 아니다 — HTTP도 DB도 손대지 않는
    // 순수 로직이라 스프링 없이도 그 자체로 단위 테스트가 되게 하려는 의도적 설계다. 그래서 이
    // 필드를 @RequiredArgsConstructor의 생성자 주입 대상에 넣으면 안 된다(넣으면 스프링이 "이
    // 타입의 빈을 찾을 수 없다"며 컨텍스트 부팅에 실패한다) — 필드 선언과 동시에 직접 new로
    // 생성해서 초기화한다. final 필드라도 선언 시점에 값을 이미 채워두면 Lombok의
    // @RequiredArgsConstructor가 이 필드를 생성자 파라미터에서 제외해준다.
    private final VisaConditionParser parser = new VisaConditionParser();

    /**
     * 국가 하나의 입국허가요건을 수집해서 upsert한다.
     *
     * <p>핵심 규칙(수기 검증 데이터 보존): {@code verified = true}인 행(Tier A, 사람이 직접 확인한
     * 데이터)은 재수집해도 판정 필드(visaRequired/visaFreeDays/passportValidityMonths)를 절대
     * 덮어쓰지 않는다 — 원문 참고자료(rawText/evidenceText/remark/sourceFetchedAt)만 최신화한다.
     * 아직 검증되지 않은 행(신규 포함)은 매번 새로 파싱한 결과로 덮어쓴다.
     *
     * <p>실패 처리: {@link EntranceVisaClient#fetch}가 재시도(최대 3회)를 다 소진하고
     * {@link ExternalApiException}을 던지면, 이 메서드는 그 예외를 잡아 로그만 남기고 조용히
     * 반환한다 — 스케줄러가 여러 국가를 순회하는 도중 한 국가의 실패가 배치 전체를 중단시키면
     * 안 되기 때문이다.
     *
     * @param country 수집 대상 국가 (Phase 0의 country 테이블 행)
     */
    // @Transactional: 이 메서드 안의 조회(findByCountryIdAndPassportType)와 저장(save)을
    // 하나의 DB 트랜잭션으로 묶는다. 중간에 예외가 나면 전부 롤백되어, 절반만 반영된 상태가 DB에
    // 남지 않는다.
    @Transactional
    public void collectOne(Country country) {
        Optional<EntranceVisaApiItem> apiItem;
        try {
            apiItem = client.fetch(country.getIsoAlpha2());
        } catch (ExternalApiException e) {
            // 재시도 소진 후에도 실패 — 이 국가만 건너뛰고 배치는 계속 진행되도록 예외를 삼킨다.
            log.warn("입국허가요건 수집 실패, 건너뜀: country={}, reason={}",
                    country.getIsoAlpha2(), e.getMessage());
            return;
        }

        if (apiItem.isEmpty()) {
            log.info("입국허가요건 응답 없음: country={}", country.getIsoAlpha2());
            return;
        }

        EntranceVisaApiItem item = apiItem.get();
        VisaRequirement requirement = repository
                .findByCountryIdAndPassportType(country.getId(), PASSPORT_TYPE_GENERAL)
                .orElseGet(() -> VisaRequirement.newUnverified(country.getId(), PASSPORT_TYPE_GENERAL));

        OffsetDateTime now = OffsetDateTime.now();
        if (requirement.isVerified()) {
            // Tier A(수기 검증 완료) — 판정 필드는 그대로 두고 원문 참고자료만 갱신한다.
            requirement.refreshSourceOnly(item.gnrlPsptVisaCn(), item.nvisaEntryEvdcCn(), item.remark(), now);
        } else {
            // 신규 또는 아직 미검증 — 파서로 새로 판정하고 판정 필드 + 원문을 함께 갱신한다.
            ParsedVisaCondition parsed = parser.parse(
                    item.gnrlPsptVisaYn(), item.gnrlPsptVisaCn(), item.nvisaEntryEvdcCn(), item.remark());
            requirement.applyCollectedData(parsed, item.gnrlPsptVisaCn(), item.nvisaEntryEvdcCn(),
                    item.remark(), now);
        }

        repository.save(requirement);
    }
}
