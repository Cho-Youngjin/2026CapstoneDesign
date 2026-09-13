package com.travelfootsteps.country;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ChecklistTemplateRepository extends JpaRepository<ChecklistTemplate, Long> {

    // "country_id가 NULL(공통) 이거나 country_id가 이 나라인" 행을 우선순위 오름차순으로 가져온다.
    // GET /api/countries/{iso2}/checklist(공통 템플릿 조회)와, TripController.create()가 여행
    // 생성 시 trip_checklist로 스냅샷 복사할 원본 목록을 고를 때 둘 다 이 메서드를 재사용한다.
    List<ChecklistTemplate> findByCountryIdIsNullOrCountryIdOrderByPriorityAsc(Long countryId);
}
