package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface TripChecklistItemRepository extends JpaRepository<TripChecklistItem, Long> {

    // GET /api/trips/{tripId}/checklist — 우선순위 오름차순으로 보여준다(checklist_template과
    // 같은 정렬 기준을 그대로 물려받는다).
    List<TripChecklistItem> findByTripIdOrderByPriorityAsc(Long tripId);

    // POST /api/trips/{tripId}/checklist/{itemId}/check — itemId가 진짜 그 tripId 소유인지까지
    // 한 번에 확인한다(TripTaskRepository.findByIdAndTripId와 같은 패턴). 이렇게 하면 "다른
    // 여행의 itemId를 넣어서 남의 체크리스트를 조작"하는 것을 쿼리 하나로 막을 수 있다.
    Optional<TripChecklistItem> findByIdAndTripId(Long id, Long tripId);
}
