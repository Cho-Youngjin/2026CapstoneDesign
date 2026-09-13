package com.travelfootsteps.footsteps;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface CheckinRepository extends JpaRepository<Checkin, Long> {
    Optional<Checkin> findByFirebaseUidAndRecordedAt(String firebaseUid, Instant recordedAt);
    List<Checkin> findByFirebaseUid(String firebaseUid);
}
