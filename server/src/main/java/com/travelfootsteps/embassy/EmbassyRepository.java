package com.travelfootsteps.embassy;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EmbassyRepository extends JpaRepository<Embassy, Long> {
    List<Embassy> findByCountryId(Long countryId);

    // EmbassyCollector의 "교체(replace)" 전략에서, 새로 수집한 공관 목록을 저장하기 전에
    // 국가의 기존 행을 전부 지우는 데 쓴다.
    void deleteByCountryId(Long countryId);
}
