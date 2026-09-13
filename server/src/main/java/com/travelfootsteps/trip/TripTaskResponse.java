package com.travelfootsteps.trip;

import java.time.LocalDate;

public record TripTaskResponse(Long id, String title, LocalDate dueDate, boolean done) {
    public static TripTaskResponse from(TripTask task) {
        return new TripTaskResponse(task.getId(), task.getTitle(), task.getDueDate(), task.isDone());
    }
}
