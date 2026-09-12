CREATE TABLE visa_requirement (
    id                         BIGSERIAL PRIMARY KEY,
    country_id                 BIGINT NOT NULL REFERENCES country(id),
    passport_type              VARCHAR(10) NOT NULL DEFAULT 'GENERAL',
    visa_required               BOOLEAN NOT NULL,
    visa_free_days               INTEGER,
    passport_validity_months     INTEGER,
    raw_text                      TEXT,
    evidence_text                 TEXT,
    remark                        TEXT,
    source_fetched_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified                       BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT visa_requirement_passport_type_check
        CHECK (passport_type IN ('GENERAL', 'OFFICIAL', 'DIPLOMATIC')),
    CONSTRAINT visa_requirement_country_passport_unique UNIQUE (country_id, passport_type)
);

CREATE INDEX idx_visa_requirement_country ON visa_requirement (country_id);
