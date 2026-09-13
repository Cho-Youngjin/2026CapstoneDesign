CREATE TABLE travel_alert (
    id         BIGSERIAL PRIMARY KEY,
    country_id BIGINT NOT NULL REFERENCES country(id),
    level      INTEGER NOT NULL,
    region     VARCHAR(100),
    title      VARCHAR(255) NOT NULL,
    issued_at  TIMESTAMPTZ NOT NULL,
    -- level 0 = UNKNOWN(파싱 실패/미확인). 1(안전)로 낙관 처리하지 않는다 — 2026-09-12 리뷰 반영.
    CONSTRAINT travel_alert_level_check CHECK (level BETWEEN 0 AND 4)
);

CREATE INDEX idx_travel_alert_country ON travel_alert (country_id);

CREATE TABLE embassy (
    id              BIGSERIAL PRIMARY KEY,
    country_id      BIGINT NOT NULL REFERENCES country(id),
    type            VARCHAR(20) NOT NULL,
    name            VARCHAR(255) NOT NULL,
    lat             DOUBLE PRECISION NOT NULL,
    lng             DOUBLE PRECISION NOT NULL,
    phone           VARCHAR(50),
    emergency_phone VARCHAR(50),
    address         VARCHAR(255)
);

CREATE INDEX idx_embassy_country ON embassy (country_id);
