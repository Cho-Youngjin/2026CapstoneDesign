package com.travelfootsteps.footsteps;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "checkin")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Checkin {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "firebase_uid", nullable = false)
    private String firebaseUid;

    @Column(nullable = false)
    private double lat;

    @Column(nullable = false)
    private double lng;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    // (firebase_uid, recorded_at) 유니크 제약의 기준 컬럼이기도 하다 — 재전송 시 중복 삽입을 막는다.
    @Column(name = "recorded_at", nullable = false)
    private Instant recordedAt;

    @Column(nullable = false, length = 10)
    private String source;

    public static Checkin of(String firebaseUid, double lat, double lng, Long countryId,
                              Instant recordedAt, String source) {
        Checkin checkin = new Checkin();
        checkin.firebaseUid = firebaseUid;
        checkin.lat = lat;
        checkin.lng = lng;
        checkin.countryId = countryId;
        checkin.recordedAt = recordedAt;
        checkin.source = source;
        return checkin;
    }
}
