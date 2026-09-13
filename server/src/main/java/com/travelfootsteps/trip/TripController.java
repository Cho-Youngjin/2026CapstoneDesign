package com.travelfootsteps.trip;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.visa.VisaJudgement;
import com.travelfootsteps.visa.VisaJudgementService;
import com.travelfootsteps.visa.VisaRequirement;
import com.travelfootsteps.visa.VisaRequirementRepository;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Objects;

// @RestController: 이 클래스의 각 메서드가 반환하는 객체(record)를 Jackson이 JSON으로 직렬화해
// HTTP 응답 본문에 그대로 실어 보낸다는 뜻이다(뷰 템플릿을 렌더링하지 않는다).
// @RequestMapping("/api/trips"): 이 컨트롤러의 모든 엔드포인트가 이 경로 아래에 매핑된다.
// @RequiredArgsConstructor(Lombok): final 필드 중 "생성자가 초기화하지 않은" 것들만 모아 생성자를
// 만들어준다 — 아래에서 직접 new로 초기화해 둔 두 필드(visaJudgementService/scheduleGenerator)는
// 이 생성자 파라미터에서 자동으로 제외된다.
@RestController
@RequestMapping("/api/trips")
@RequiredArgsConstructor
public class TripController {

    // 이 수집기 계열이 다루는 것은 일반 여권(GENERAL)뿐이다 — Task 3의 VisaRequirementCollector가
    // 채우는 범위와 맞춘다.
    private static final String PASSPORT_TYPE_GENERAL = "GENERAL";

    private final CountryRepository countryRepository;
    private final VisaRequirementRepository visaRequirementRepository;
    private final TripRepository tripRepository;
    private final TripTaskRepository tripTaskRepository;

    // 주의: VisaJudgementService와 ScheduleGenerator는 둘 다 (Task 5의 설계상) 스프링 빈이
    // 아니다 — DB에도 HTTP에도 접근하지 않는 순수 로직이라 스프링 없이 바로 단위 테스트가
    // 되도록 의도적으로 @Component를 붙이지 않았다. 그래서 @RequiredArgsConstructor의 생성자
    // 주입 대상에 넣으면 안 된다(넣으면 "이 타입의 빈을 찾을 수 없다"며 스프링 컨텍스트 부팅
    // 자체가 실패한다) — 필드 선언과 동시에 직접 new로 생성해서 초기화한다.
    private final VisaJudgementService visaJudgementService = new VisaJudgementService();
    private final ScheduleGenerator scheduleGenerator = new ScheduleGenerator();

    // @Transactional: 여행 한 건 저장 + 준비물 여러 건 저장을 하나의 DB 트랜잭션으로 묶는다.
    // 준비물을 만드는 도중 하나라도 실패하면(예: DB 커넥션 문제) 방금 저장한 trip과 그 전까지
    // 저장한 trip_task까지 전부 롤백되어, "여행은 있는데 준비물 일부만 있는" 반쪽짜리 상태가
    // DB에 남지 않는다.
    @Transactional
    @PostMapping
    public TripResponse create(@Valid @RequestBody CreateTripRequest request, Authentication authentication) {
        Country country = findCountryOrThrow(request.countryIso2());
        VisaRequirement requirement = findRequirement(country);
        VisaJudgement judgement = visaJudgementService.judge(requirement, request.departDate(),
                request.returnDate(), request.passportExpiry());

        // 판정을 "이번 한 번만" 계산해서 곧바로 스냅샷으로 굳힌다. 이 create() 메서드 밖에서는
        // (refresh()를 빼고는) 절대 judge()를 다시 부르지 않는다 — 클래스 상단 주석 참고.
        Trip trip = Trip.create(authentication.getName(), country.getId(),
                request.departDate(), request.returnDate(), request.passportExpiry());
        trip.applyJudgementSnapshot(judgement, requirementUpdatedAt(requirement));
        trip = tripRepository.save(trip);

        List<TripTask> tasks = generateAndSaveTasks(trip, request.departDate(), judgement);

        // 방금 막 스냅샷을 만들었으므로 이 시점의 staleness는 항상 false여야 정상이다. 그래도
        // "현재 DB 상태와 스냅샷을 비교한다"는 동일한 로직을 GET/refresh와 공유하기 위해
        // isJudgementStale()을 그대로 호출한다(하드코딩된 false를 두지 않는다).
        boolean stale = isJudgementStale(trip, country);
        return TripResponse.of(trip, country, tasks, stale);
    }

    // GET은 저장된 스냅샷만 읽는다 — VisaJudgementService.judge()를 호출하지 않는다. 이유는
    // 클래스 상단 및 Trip.applyJudgementSnapshot() 문서에 설명한 대로다: 원본 visa_requirement가
    // 여행 생성 이후 바뀌어도, 이미 확정된 여행의 판정과 준비 일정(및 앱이 예약해 둔 로컬 알람)이
    // 조용히 어긋나면 안 된다. 대신 "판정 기준이 그 사이에 바뀌었는지"만 judgementStale로
    // 알려주고, 실제로 다시 계산할지는 사용자가 POST /refresh로 명시적으로 동의해야 한다.
    @GetMapping("/{id}")
    public TripResponse get(@PathVariable Long id, Authentication authentication) {
        Trip trip = findOwnedTripOrThrow(id, authentication.getName());
        Country country = findCountryByIdOrThrow(trip.getCountryId());
        List<TripTask> tasks = tripTaskRepository.findByTripIdOrderByDueDateAsc(trip.getId());

        boolean stale = isJudgementStale(trip, country);
        return TripResponse.of(trip, country, tasks, stale);
    }

    // 사용자가 (앱의 확인 다이얼로그를 거쳐) 명시적으로 새로고침에 동의했을 때만 호출되는
    // 엔드포인트다. judge()를 다시 계산해 스냅샷을 덮어쓰고, 기존 준비물을 전부 지운 뒤 새
    // 일정으로 다시 만든다. 이미 완료 체크한 준비물의 done 상태는 이 캡스톤 규모에서는 보존하지
    // 않는다 — "새로고침하면 완료 체크가 초기화될 수 있다"는 안내는 앱(Plan B) 쪽 확인
    // 다이얼로그가 책임진다.
    @Transactional
    @PostMapping("/{id}/refresh")
    public TripResponse refresh(@PathVariable Long id, Authentication authentication) {
        Trip trip = findOwnedTripOrThrow(id, authentication.getName());
        Country country = findCountryByIdOrThrow(trip.getCountryId());
        VisaRequirement requirement = findRequirement(country);
        VisaJudgement judgement = visaJudgementService.judge(requirement, trip.getDepartDate(),
                trip.getReturnDate(), trip.getPassportExpiry());

        trip.applyJudgementSnapshot(judgement, requirementUpdatedAt(requirement));
        trip = tripRepository.save(trip);

        // 기존 준비물을 전부 지우고 새 판정 기준으로 다시 만든다 — 부분적으로 섞이면(옛 판정
        // 기준의 항목 일부 + 새 판정 기준의 항목 일부) 오히려 더 헷갈리는 상태가 된다.
        tripTaskRepository.deleteByTripId(trip.getId());
        List<TripTask> tasks = generateAndSaveTasks(trip, trip.getDepartDate(), judgement);

        boolean stale = isJudgementStale(trip, country);
        return TripResponse.of(trip, country, tasks, stale);
    }

    @PostMapping("/{id}/tasks/{taskId}/done")
    public TripTaskResponse markTaskDone(@PathVariable Long id, @PathVariable Long taskId,
                                          Authentication authentication) {
        findOwnedTripOrThrow(id, authentication.getName());
        TripTask task = tripTaskRepository.findByIdAndTripId(taskId, id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "준비물 항목을 찾을 수 없습니다"));
        task.markDone();
        tripTaskRepository.save(task);
        return TripTaskResponse.from(task);
    }

    private List<TripTask> generateAndSaveTasks(Trip trip, LocalDate departDate, VisaJudgement judgement) {
        return scheduleGenerator.generate(departDate, judgement).stream()
                .map(t -> tripTaskRepository.save(TripTask.create(trip.getId(), t.title(), t.dueDate())))
                .toList();
    }

    // GENERAL 여권 기준 visa_requirement 행. 아직 수집되지 않은 나라면 null(judge()가 이 경우
    // UNVERIFIED로 판정한다 — VisaJudgementService 문서 참고).
    private VisaRequirement findRequirement(Country country) {
        return visaRequirementRepository
                .findByCountryIdAndPassportType(country.getId(), PASSPORT_TYPE_GENERAL)
                .orElse(null);
    }

    private OffsetDateTime requirementUpdatedAt(VisaRequirement requirement) {
        return requirement != null ? requirement.getSourceFetchedAt() : null;
    }

    // 스냅샷에 저장된 requirement_updated_at과 "그 나라의 현재" source_fetched_at을 비교한다.
    // 다르면(둘 중 하나만 null인 경우 포함 — 예: 생성 당시엔 미수집이었는데 이후 처음 수집됐다)
    // 원본 데이터가 스냅샷 이후 바뀐 것이므로 true를 반환한다. Objects.equals를 쓰는 이유는
    // 두 값 다 null일 수 있어서(둘 다 아직 미수집이면 안 바뀐 것 = false여야 한다)다.
    private boolean isJudgementStale(Trip trip, Country country) {
        OffsetDateTime currentRequirementUpdatedAt = requirementUpdatedAt(findRequirement(country));
        return !Objects.equals(currentRequirementUpdatedAt, trip.getRequirementUpdatedAt());
    }

    private Trip findOwnedTripOrThrow(Long id, String uid) {
        Trip trip = tripRepository.findById(id).orElseThrow(() -> new TripNotFoundException(id));
        if (!trip.belongsTo(uid)) {
            // 소유자가 아니면 존재 여부 자체를 감춘다(404) — 403으로 존재를 알려주지 않는다.
            throw new TripNotFoundException(id);
        }
        return trip;
    }

    private Country findCountryOrThrow(String iso2) {
        return countryRepository.findByIsoAlpha2(iso2.toUpperCase())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가를 찾을 수 없습니다: " + iso2));
    }

    private Country findCountryByIdOrThrow(Long countryId) {
        return countryRepository.findById(countryId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "국가 데이터 손상"));
    }
}
