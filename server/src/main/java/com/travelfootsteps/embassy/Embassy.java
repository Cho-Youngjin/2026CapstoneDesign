package com.travelfootsteps.embassy;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

// @Entity + @Table: embassy 테이블(V3 마이그레이션) 한 줄과 매핑된다.
// 재외공관도 여행경보와 마찬가지로 국가당 여러 건(대사관/영사관 등)이 나올 수 있으므로,
// EmbassyCollector가 국가의 기존 행을 지우고 새로 받아온 것으로 교체하는 전략을 쓴다.
@Entity
@Table(name = "embassy")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Embassy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id", nullable = false)
    private Long countryId;

    // type: "대사관", "총영사관" 등 공관 종류. 값 목록을 DB CHECK로 강제하지 않는 이유는
    // 공공API가 내려주는 표현이 고정되어 있지 않아서다(EmbassyCollector가 null이면
    // "대사관"으로 기본값을 채운다).
    @Column(nullable = false, length = 20)
    private String type;

    @Column(nullable = false, length = 255)
    private String name;

    // 지도 핀을 찍기 위한 위경도. nullable=false지만 EmbassyCollector가 저장 전에
    // 좌표가 없는 항목은 걸러낸다(핀을 만들 수 없으므로).
    @Column(nullable = false)
    private double lat;

    @Column(nullable = false)
    private double lng;

    @Column(length = 50)
    private String phone;

    @Column(name = "emergency_phone", length = 50)
    private String emergencyPhone;

    @Column(length = 255)
    private String address;

    @Builder
    public Embassy(Long countryId, String type, String name, double lat, double lng,
                    String phone, String emergencyPhone, String address) {
        this.countryId = countryId;
        this.type = type;
        this.name = name;
        this.lat = lat;
        this.lng = lng;
        this.phone = phone;
        this.emergencyPhone = emergencyPhone;
        this.address = address;
    }
}
