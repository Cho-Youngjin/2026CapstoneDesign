package com.travelfootsteps.country;

// GET /api/countries/{iso2}/checklist의 응답 항목이다. 읽기 전용 "공통 템플릿" 조회이므로
// checked 필드가 없다 — 사용자별 체크 상태는 여행에 귀속된 trip_checklist 쪽
// (com.travelfootsteps.trip.TripChecklistItemResponse)의 몫이다.
public record ChecklistTemplateResponse(Long id, String category, String title, String description, int priority) {
    public static ChecklistTemplateResponse from(ChecklistTemplate t) {
        return new ChecklistTemplateResponse(t.getId(), t.getCategory(), t.getTitle(), t.getDescription(), t.getPriority());
    }
}
