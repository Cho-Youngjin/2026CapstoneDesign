package com.travelfootsteps.footsteps;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface DailyStepRepository extends JpaRepository<DailyStep, Long> {
    Optional<DailyStep> findByFirebaseUidAndDateAndCountryId(String firebaseUid, LocalDate date, Long countryId);
    List<DailyStep> findByFirebaseUid(String firebaseUid);
}
