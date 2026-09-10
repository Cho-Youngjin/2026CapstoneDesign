CREATE TABLE country (
    id                  BIGSERIAL PRIMARY KEY,
    iso_alpha2          CHAR(2)      NOT NULL UNIQUE,
    iso_alpha3          CHAR(3),
    name_ko             VARCHAR(100) NOT NULL,
    name_en             VARCHAR(100),
    continent           VARCHAR(50),
    tier                CHAR(1)      NOT NULL DEFAULT 'B',
    plug_types          VARCHAR(50),
    voltage_v           INTEGER,
    frequency_hz        INTEGER,
    currency_code       CHAR(3),
    card_acceptance     VARCHAR(10),
    power_bank_wh_limit INTEGER,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT country_tier_check CHECK (tier IN ('A', 'B')),
    CONSTRAINT country_card_acceptance_check
        CHECK (card_acceptance IS NULL OR card_acceptance IN ('HIGH', 'MEDIUM', 'LOW'))
);

CREATE INDEX idx_country_tier ON country (tier);

-- Tier A 20개국 시드 (상세 정보는 Plan A의 배치 수집과 R4의 수기 검증으로 채운다)
INSERT INTO country (iso_alpha2, iso_alpha3, name_ko, name_en, continent, tier) VALUES
('JP', 'JPN', '일본',       'Japan',          'Asia',    'A'),
('VN', 'VNM', '베트남',     'Vietnam',        'Asia',    'A'),
('TH', 'THA', '태국',       'Thailand',       'Asia',    'A'),
('US', 'USA', '미국',       'United States',  'America', 'A'),
('PH', 'PHL', '필리핀',     'Philippines',    'Asia',    'A'),
('CN', 'CHN', '중국',       'China',          'Asia',    'A'),
('TW', 'TWN', '대만',       'Taiwan',         'Asia',    'A'),
('SG', 'SGP', '싱가포르',   'Singapore',      'Asia',    'A'),
('HK', 'HKG', '홍콩',       'Hong Kong',      'Asia',    'A'),
('FR', 'FRA', '프랑스',     'France',         'Europe',  'A'),
('IT', 'ITA', '이탈리아',   'Italy',          'Europe',  'A'),
('ES', 'ESP', '스페인',     'Spain',          'Europe',  'A'),
('DE', 'DEU', '독일',       'Germany',        'Europe',  'A'),
('GB', 'GBR', '영국',       'United Kingdom', 'Europe',  'A'),
('AU', 'AUS', '호주',       'Australia',      'Oceania', 'A'),
('TR', 'TUR', '튀르키예',   'Turkey',         'Europe',  'A'),
('CH', 'CHE', '스위스',     'Switzerland',    'Europe',  'A'),
('CZ', 'CZE', '체코',       'Czechia',        'Europe',  'A'),
('ID', 'IDN', '인도네시아', 'Indonesia',      'Asia',    'A'),
('CA', 'CAN', '캐나다',     'Canada',         'America', 'A');
