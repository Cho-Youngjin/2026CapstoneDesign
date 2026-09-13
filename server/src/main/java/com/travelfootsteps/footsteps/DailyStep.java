package com.travelfootsteps.footsteps;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

@Entity
@Table(name = "daily_steps",
        uniqueConstraints = @UniqueConstraint(columnNames = {"firebase_uid", "date", "country_id"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class DailyStep {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "firebase_uid", nullable = false)
    private String firebaseUid;

    @Column(nullable = false)
    private LocalDate date;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    @Column(name = "step_count", nullable = false)
    private int stepCount;

    public static DailyStep of(String firebaseUid, LocalDate date, Long countryId, int stepCount) {
        DailyStep dailyStep = new DailyStep();
        dailyStep.firebaseUid = firebaseUid;
        dailyStep.date = date;
        dailyStep.countryId = countryId;
        dailyStep.stepCount = stepCount;
        return dailyStep;
    }

    public void updateStepCount(int stepCount) {
        this.stepCount = stepCount;
    }
}
