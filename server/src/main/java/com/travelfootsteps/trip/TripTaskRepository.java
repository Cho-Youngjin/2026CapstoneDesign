package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface TripTaskRepository extends JpaRepository<TripTask, Long> {

    // GET /api/trips/{id}가 준비물 목록을 마감일 오름차순으로 보여줄 때 쓴다.
    List<TripTask> findByTripIdOrderByDueDateAsc(Long tripId);

    // POST /api/trips/{id}/tasks/{taskId}/done — taskId가 진짜 그 tripId 소유인지까지 한 번에
    // 확인한다. 이렇게 하면 "다른 여행의 taskId를 넣어서 남의 준비물을 완료 처리"하는 것을
    // 쿼리 하나로 막을 수 있다.
    Optional<TripTask> findByIdAndTripId(Long id, Long tripId);

    // POST /api/trips/{id}/refresh — 새로고침 시 기존 준비물을 전부 지우고 새로 만든다(완료
    // 여부는 이 캡스톤 규모에서는 보존하지 않는다 — 브리프의 명시적 설계 결정).
    void deleteByTripId(Long tripId);
}
