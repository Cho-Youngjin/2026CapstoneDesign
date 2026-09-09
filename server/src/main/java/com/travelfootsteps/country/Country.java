package com.travelfootsteps.country;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Entity
@Table(name = "country")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Country {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "iso_alpha2", nullable = false, unique = true, length = 2, columnDefinition = "CHAR(2)")
    private String isoAlpha2;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "iso_alpha3", length = 3, columnDefinition = "CHAR(3)")
    private String isoAlpha3;

    @Column(name = "name_ko", nullable = false, length = 100)
    private String nameKo;

    @Column(name = "name_en", length = 100)
    private String nameEn;

    @Column(length = 50)
    private String continent;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(nullable = false, length = 1, columnDefinition = "CHAR(1)")
    private String tier;

    @Column(name = "plug_types", length = 50)
    private String plugTypes;

    @Column(name = "voltage_v")
    private Integer voltageV;

    @Column(name = "frequency_hz")
    private Integer frequencyHz;

    @JdbcTypeCode(SqlTypes.CHAR)
    @Column(name = "currency_code", length = 3, columnDefinition = "CHAR(3)")
    private String currencyCode;

    @Column(name = "card_acceptance", length = 10)
    private String cardAcceptance;

    @Column(name = "power_bank_wh_limit")
    private Integer powerBankWhLimit;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;
}
