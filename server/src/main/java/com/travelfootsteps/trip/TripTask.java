package com.travelfootsteps.trip;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;

// @Entity + @Table(name = "trip_task"): trip_task 테이블의 한 행과 매핑되는 JPA 엔티티다.
// 준비물 항목(예: "여권 재발급", "비자 신청") 하나가 이 테이블의 한 행이다. 여행이 삭제되면
// (V4__trip.sql의 ON DELETE CASCADE 덕분에) 이 행들도 DB 레벨에서 함께 삭제된다.
@Entity
@Table(name = "trip_task")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TripTask {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "trip_id", nullable = false)
    private Long tripId;

    @Column(nullable = false, length = 100)
    private String title;

    @Column(name = "due_date", nullable = false)
    private LocalDate dueDate;

    @Column(nullable = false)
    private boolean done;

    public static TripTask create(Long tripId, String title, LocalDate dueDate) {
        TripTask task = new TripTask();
        task.tripId = tripId;
        task.title = title;
        task.dueDate = dueDate;
        task.done = false;
        return task;
    }

    public void markDone() {
        this.done = true;
    }
}
