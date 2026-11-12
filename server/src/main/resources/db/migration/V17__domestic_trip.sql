-- 국내 여행(설계 2026-11-07 9-1). trip.country_id는 country 행을 가리켜야 하므로(외래 키) 본국(한국)을
-- 국가 표에 넣는다. 목적지 목록(GET /api/countries)과 일일 공공데이터 수집은 이 행을 건너뛴다
-- (Country.HOME_ISO2). 통화 코드는 비워 둔다 — 원화는 환율 수집 대상이 아니다.
INSERT INTO country (iso_alpha2, iso_alpha3, name_ko, name_en, continent, tier)
VALUES ('KR', 'KOR', '대한민국', 'South Korea', 'Asia', 'A');

-- 국내 여행에는 여권 만료일이 없다. 해외 여행은 요청 검증(CreateTripRequest)이 여전히 필수로 막는다.
ALTER TABLE trip ALTER COLUMN passport_expiry DROP NOT NULL;
