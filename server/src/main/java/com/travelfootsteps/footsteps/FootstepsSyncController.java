package com.travelfootsteps.footsteps;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class FootstepsSyncController {

    private final CountryRepository countryRepository;
    private final CheckinRepository checkinRepository;
    private final DailyStepRepository dailyStepRepository;

    @PostMapping("/checkins")
    public List<SyncResultItem> syncCheckins(@RequestBody List<CheckinSyncRequest> items,
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
        return checkinRepository.findByFirebaseUid(authentication.getName()).stream()
                .map(CheckinResponse::from)
                .toList();
    }

    @PostMapping("/daily-steps")
    public List<SyncResultItem> syncDailySteps(@RequestBody List<DailyStepSyncRequest> items,
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
        return dailyStepRepository.findByFirebaseUid(authentication.getName()).stream()
                .map(DailyStepResponse::from)
                .toList();
    }

    // (uid, recordedAt) 유니크 제약 덕분에 같은 이벤트가 재전송돼도 새 행을 만들지 않고
    // 기존 행을 그대로 반환한다 — 네트워크 재시도로 인한 중복 체크인을 막는다.
    private Checkin upsertCheckin(String uid, CheckinSyncRequest item, Long countryId) {
        return checkinRepository.findByFirebaseUidAndRecordedAt(uid, item.recordedAt())
                .orElseGet(() -> checkinRepository.save(Checkin.of(uid,
                        item.lat(), item.lng(), countryId, item.recordedAt(), item.source())));
    }

    private DailyStep upsertDailyStep(String uid, LocalDate date, Long countryId, int stepCount) {
        return dailyStepRepository.findByFirebaseUidAndDateAndCountryId(uid, date, countryId)
                .map(existing -> {
                    existing.updateStepCount(stepCount);
                    return existing;
                })
                .orElseGet(() -> dailyStepRepository.save(DailyStep.of(uid, date, countryId, stepCount)));
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "알 수 없는 국가 코드: " + iso2));
    }
}
