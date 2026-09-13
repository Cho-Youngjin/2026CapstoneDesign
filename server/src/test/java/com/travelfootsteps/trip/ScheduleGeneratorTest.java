package com.travelfootsteps.trip;

import com.travelfootsteps.visa.VisaJudgement;
import com.travelfootsteps.visa.VisaVerdict;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ScheduleGeneratorTest {

    private final ScheduleGenerator generator = new ScheduleGenerator();

    @Test
    void 여권_문제없고_무비자_가능이면_여권재발급과_비자신청_항목이_없다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.VISA_FREE_OK, 20, 45, true, 6, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title)
                .doesNotContain("여권 재발급", "비자 신청");
        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title)
                .contains("항공권·숙소 확정", "여행자보험 가입", "준비물 구매", "환전", "최종 서류 점검");
    }

    @Test
    void 여권_미달이면_D90에_여권_재발급_항목이_생긴다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.VISA_FREE_OK, 20, 45, false, 6, 65);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).anySatisfy(t -> {
            assertThat(t.title()).isEqualTo("여권 재발급");
            assertThat(t.dueDate()).isEqualTo(LocalDate.of(2026, 9, 21));
        });
    }

    @Test
    void 비자_필요_또는_초과면_D45에_비자_신청_항목이_생긴다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement required = new VisaJudgement(VisaVerdict.VISA_REQUIRED, 20, 0, true, null, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, required);

        assertThat(tasks).anySatisfy(t -> {
            assertThat(t.title()).isEqualTo("비자 신청");
            assertThat(t.dueDate()).isEqualTo(LocalDate.of(2026, 11, 5));
        });
    }

    @Test
    void 무비자_초과도_비자_신청_항목이_생긴다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement exceeded = new VisaJudgement(VisaVerdict.VISA_FREE_EXCEEDED, 30, 15, true, null, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, exceeded);

        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title).contains("비자 신청");
    }

    @Test
    void 공통_항목의_기준일은_출발일로부터_역산된다() {
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.VISA_FREE_OK, 20, 45, true, null, null);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).anySatisfy(t -> {
            assertThat(t.title()).isEqualTo("최종 서류 점검");
            assertThat(t.dueDate()).isEqualTo(LocalDate.of(2026, 12, 13)); // D-7
        });
    }

    @Test
    void UNVERIFIED_판정이어도_여권_문제가_있으면_여권_재발급_항목이_생긴다() {
        // ScheduleGenerator는 verdict가 아니라 passportOk만으로 여권 재발급 여부를 판단한다 —
        // UNVERIFIED(예: 아직 수집되지 않은 나라)라도 여권 자체는 문제가 될 수 있으므로 이 조합도
        // 정상적으로 항목을 만들어야 한다.
        LocalDate depart = LocalDate.of(2026, 12, 20);
        VisaJudgement judgement = new VisaJudgement(VisaVerdict.UNVERIFIED, 20, null, false, null, 10);

        List<ScheduleGenerator.GeneratedTask> tasks = generator.generate(depart, judgement);

        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title).contains("여권 재발급");
        assertThat(tasks).extracting(ScheduleGenerator.GeneratedTask::title).doesNotContain("비자 신청");
    }
}
