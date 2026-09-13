package com.travelfootsteps.trip;

import com.travelfootsteps.visa.VisaJudgement;
import com.travelfootsteps.visa.VisaVerdict;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * 스펙 §6-①의 역산 일정을 만든다. departDate 기준으로 역산하며, 이미 지난 날짜를
 * "지금 바로"로 표시하는 것은 앱(Plan B)의 화면 책임이다 — 여기서는 실제 날짜만 계산한다.
 *
 * <p>이 클래스는 Spring 빈이 아니다 — DB에도, HTTP에도 접근하지 않는 순수 로직이라 스프링
 * 없이 바로 단위 테스트로 검증할 수 있다. Task 6의 TripController가 이 클래스를 직접
 * {@code new}로 생성해 호출하고, 반환된 목록으로 {@code trip_task} 행을 만든다.
 */
public class ScheduleGenerator {

    public record GeneratedTask(String title, LocalDate dueDate) {
    }

    public List<GeneratedTask> generate(LocalDate departDate, VisaJudgement judgement) {
        List<GeneratedTask> tasks = new ArrayList<>();

        if (!judgement.passportOk()) {
            tasks.add(new GeneratedTask("여권 재발급", departDate.minusDays(90)));
        }
        if (judgement.verdict() == VisaVerdict.VISA_REQUIRED
                || judgement.verdict() == VisaVerdict.VISA_FREE_EXCEEDED) {
            tasks.add(new GeneratedTask("비자 신청", departDate.minusDays(45)));
        }

        tasks.add(new GeneratedTask("항공권·숙소 확정", departDate.minusDays(30)));
        tasks.add(new GeneratedTask("여행자보험 가입", departDate.minusDays(30)));
        tasks.add(new GeneratedTask("준비물 구매", departDate.minusDays(14)));
        tasks.add(new GeneratedTask("환전", departDate.minusDays(14)));
        tasks.add(new GeneratedTask("최종 서류 점검", departDate.minusDays(7)));

        return tasks;
    }
}
