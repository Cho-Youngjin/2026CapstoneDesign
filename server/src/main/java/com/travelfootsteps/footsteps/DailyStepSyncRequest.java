package com.travelfootsteps.footsteps;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

import java.time.LocalDate;

public record DailyStepSyncRequest(
        Long localId,
        // 사용자의 로컬 달력 날짜(steps가 기록된 "그 날")를 순수 yyyy-MM-dd 문자열로 보낸다 —
        // 시각도 타임존도 없다. 서버는 이 값에 대해 어떤 타임존 변환도 하지 않는다(의도적 설계):
        // 만약 클라이언트가 UTC 순간(instant)을 통째로 보내고 서버가 이를 날짜로 잘라낸다면,
        // 로컬 자정 근처에 기록된 걸음수가 실제와 다른 날짜로 잘못 귀속될 수 있다. 그래서
        // 타임존 변환 책임은 전적으로 클라이언트(로컬 달력 날짜를 정확히 아는 쪽)에 있다.
        @NotNull LocalDate date,
        @NotBlank String countryIso,
        @PositiveOrZero int stepCount
) {
}
