package com.travelfootsteps.trip;

// GET /api/trips/{tripId}/checklist의 목록 항목이자, POST .../check의 응답(갱신된 항목 하나)
// 이기도 하다. 진행률(%)은 이 계획서에서 별도 엔드포인트로 만들지 않는다 — 앱이 이 목록의
// checked 개수를 세어 계산한다(과설계 방지, 2026-09-12 리뷰).
public record TripChecklistItemResponse(
        Long id, String category, String title, String description, int priority, boolean checked
) {
    public static TripChecklistItemResponse from(TripChecklistItem item) {
        return new TripChecklistItemResponse(
                item.getId(), item.getCategory(), item.getTitle(), item.getDescription(),
                item.getPriority(), item.isChecked()
        );
    }
}
