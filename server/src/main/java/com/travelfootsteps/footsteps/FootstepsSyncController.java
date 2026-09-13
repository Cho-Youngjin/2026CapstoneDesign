package com.travelfootsteps.footsteps;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class FootstepsSyncController {

    private final CountryRepository countryRepository;
    private final CheckinRepository checkinRepository;
    private final DailyStepRepository dailyStepRepository;

    @PostMapping("/checkins")
    public List<SyncResultItem> syncCheckins(@RequestBody @Valid List<CheckinSyncRequest> items,
                                              Authentication authentication) {
        String uid = authentication.getName();
        return items.stream()
                .map(item -> {
                    Country country = findCountryOrThrow(item.countryIso());
                    Checkin saved = upsertCheckin(uid, item, country.getId());
                    return new SyncResultItem(item.localId(), saved.getId().toString());
                })
                .toList();
    }

    @GetMapping("/checkins")
    public List<CheckinResponse> listCheckins(Authentication authentication) {
        List<Checkin> checkins = checkinRepository.findByFirebaseUid(authentication.getName());
        Map<Long, String> isoByCountryId = isoByCountryId(checkins.stream().map(Checkin::getCountryId).toList());
        return checkins.stream()
                .map(checkin -> CheckinResponse.from(checkin, isoByCountryId.get(checkin.getCountryId())))
                .toList();
    }

    @PostMapping("/daily-steps")
    public List<SyncResultItem> syncDailySteps(@RequestBody @Valid List<DailyStepSyncRequest> items,
                                                Authentication authentication) {
        String uid = authentication.getName();
        return items.stream()
                .map(item -> {
                    Country country = findCountryOrThrow(item.countryIso());
                    DailyStep saved = upsertDailyStep(uid, item.date(), country.getId(), item.stepCount());
                    return new SyncResultItem(item.localId(), saved.getId().toString());
                })
                .toList();
    }

    @GetMapping("/daily-steps")
    public List<DailyStepResponse> listDailySteps(Authentication authentication) {
        List<DailyStep> dailySteps = dailyStepRepository.findByFirebaseUid(authentication.getName());
        Map<Long, String> isoByCountryId = isoByCountryId(dailySteps.stream().map(DailyStep::getCountryId).toList());
        return dailySteps.stream()
                .map(dailyStep -> DailyStepResponse.from(dailyStep, isoByCountryId.get(dailyStep.getCountryId())))
                .toList();
    }

    // (uid, recordedAt) 유니크 제약 덕분에 같은 이벤트가 재전송돼도 새 행을 만들지 않고
    // 기존 행을 그대로 반환한다 — 네트워크 재시도로 인한 중복 체크인을 막는다.
    private Checkin upsertCheckin(String uid, CheckinSyncRequest item, Long countryId) {
        return checkinRepository.findByFirebaseUidAndRecordedAt(uid, item.recordedAt())
                .orElseGet(() -> checkinRepository.save(Checkin.of(uid,
                        item.lat(), item.lng(), countryId, item.recordedAt(), item.source())));
    }

    // OSIV(open-in-view)가 꺼져 있어 findBy...()가 반환하는 시점에 이미 영속성 컨텍스트가
    // 닫혀 있다 — existing은 detached 상태이므로, mutate만 하고 save()를 호출하지 않으면
    // 메모리상의 객체만 바뀌고 DB에는 반영되지 않는다(TripController.markTaskDone()과 같은
    // 패턴으로 명시적 save()가 필요하다).
    private DailyStep upsertDailyStep(String uid, LocalDate date, Long countryId, int stepCount) {
        return dailyStepRepository.findByFirebaseUidAndDateAndCountryId(uid, date, countryId)
                .map(existing -> {
                    existing.updateStepCount(stepCount);
                    return dailyStepRepository.save(existing);
                })
                .orElseGet(() -> dailyStepRepository.save(DailyStep.of(uid, date, countryId, stepCount)));
    }

    // 복원 조회 응답에 countryIso를 채우기 위한 country_id -> iso_alpha2 매핑을 한 번의 쿼리로
    // 만든다(N+1 방지) — CountryController/CountryResponse가 내부 PK를 아예 노출하지 않는 것과
    // 같은 이유로, 이 두 응답도 PK 대신 ISO 코드를 돌려줘야 클라이언트가 국가 정보를 복원할 수 있다.
    private Map<Long, String> isoByCountryId(List<Long> countryIds) {
        return countryRepository.findAllById(countryIds.stream().distinct().toList()).stream()
                .collect(Collectors.toMap(Country::getId, Country::getIsoAlpha2));
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "알 수 없는 국가 코드: " + iso2));
    }
}
