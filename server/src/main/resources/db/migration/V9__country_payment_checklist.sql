-- ============================================================
-- 초안 데이터. 임시로 작성해서 넣어두었고, 조사해서 정보 보충할 예정.
-- ============================================================


UPDATE country SET plug_types = 'A, B', voltage_v = 100, frequency_hz = 50, currency_code = 'JPY', card_acceptance = 'MEDIUM', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'JP';
UPDATE country SET plug_types = 'A, C, G', voltage_v = 220, frequency_hz = 50, currency_code = 'VND', card_acceptance = 'LOW', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'VN';
UPDATE country SET plug_types = 'A, B, C, O', voltage_v = 220, frequency_hz = 50, currency_code = 'THB', card_acceptance = 'MEDIUM', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'TH';
UPDATE country SET plug_types = 'A, B', voltage_v = 120, frequency_hz = 60, currency_code = 'USD', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'US';
UPDATE country SET plug_types = 'A, B, C', voltage_v = 220, frequency_hz = 60, currency_code = 'PHP', card_acceptance = 'LOW', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'PH';
UPDATE country SET plug_types = 'A, C, I', voltage_v = 220, frequency_hz = 50, currency_code = 'CNY', card_acceptance = 'MEDIUM', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'CN';
UPDATE country SET plug_types = 'A, B', voltage_v = 110, frequency_hz = 60, currency_code = 'TWD', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'TW';
UPDATE country SET plug_types = 'G', voltage_v = 230, frequency_hz = 50, currency_code = 'SGD', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'SG';
UPDATE country SET plug_types = 'G', voltage_v = 220, frequency_hz = 50, currency_code = 'HKD', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'HK';
UPDATE country SET plug_types = 'C, E', voltage_v = 230, frequency_hz = 50, currency_code = 'EUR', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'FR';
UPDATE country SET plug_types = 'C, F, L', voltage_v = 230, frequency_hz = 50, currency_code = 'EUR', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'IT';
UPDATE country SET plug_types = 'C, F', voltage_v = 230, frequency_hz = 50, currency_code = 'EUR', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'ES';
UPDATE country SET plug_types = 'C, F', voltage_v = 230, frequency_hz = 50, currency_code = 'EUR', card_acceptance = 'MEDIUM', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'DE';
UPDATE country SET plug_types = 'G', voltage_v = 230, frequency_hz = 50, currency_code = 'GBP', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'GB';
UPDATE country SET plug_types = 'I', voltage_v = 230, frequency_hz = 50, currency_code = 'AUD', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'AU';
UPDATE country SET plug_types = 'C, F', voltage_v = 230, frequency_hz = 50, currency_code = 'TRY', card_acceptance = 'MEDIUM', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'TR';
UPDATE country SET plug_types = 'C, J', voltage_v = 230, frequency_hz = 50, currency_code = 'CHF', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'CH';
UPDATE country SET plug_types = 'C, E', voltage_v = 230, frequency_hz = 50, currency_code = 'CZK', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'CZ';
UPDATE country SET plug_types = 'C, F', voltage_v = 230, frequency_hz = 50, currency_code = 'IDR', card_acceptance = 'LOW', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'ID';
UPDATE country SET plug_types = 'A, B', voltage_v = 120, frequency_hz = 60, currency_code = 'CAD', card_acceptance = 'HIGH', power_bank_wh_limit = 160 WHERE iso_alpha2 = 'CA';

-- ---------- 2) 나라별 준비물 특이사항 (category: PAYMENT) ----------
-- 공통 항목(country_id NULL)은 이미 V5에 있으므로, 여기서는 국가별로만 추가한다.

INSERT INTO checklist_template (country_id, category, title, description, priority) VALUES
((SELECT id FROM country WHERE iso_alpha2 = 'JP'), 'PAYMENT', '동전 지갑', '현금 결제가 많아 동전이 빠르게 쌓임. 편의점 ATM(세븐일레븐 등)에서 인출 가능.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'VN'), 'PAYMENT', '소액권 현지통화 사전 환전', '카드 결제 어려운 노점·시장 대비 소액권(1만~5만 동)을 확보한다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'TH'), 'PAYMENT', '소액권 현지통화', '야시장·수상시장 등에서는 현금만 통용되는 경우가 많다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'US'), 'PAYMENT', '팁용 소액 현금($1~5권)', '식당·택시 등 팁 문화. 카드 결제 시에도 팁 비율 선택 화면이 뜬다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'PH'), 'PAYMENT', '소액 현금', '도서 지역·지방은 카드망이 불안정한 경우가 많다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'CN'), 'PAYMENT', '알리페이/위챗페이 해외카드 연동', '사실상 표준 결제 수단. 출국 전 앱 설치 및 해외카드 등록을 시도하고, 예비 현금도 준비한다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'TW'), 'PAYMENT', '이지카드(EasyCard)', '편의점·대중교통 결제에 편리하며 공항·편의점에서 구매 가능하다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'SG'), 'PAYMENT', '이지링크(EZ-Link) 카드', '대중교통·소액 결제용으로 공항에서 구매 가능하다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'HK'), 'PAYMENT', '옥토퍼스카드', '대중교통·편의점 결제 표준으로 공항에서 구매 가능하다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'FR'), 'PAYMENT', '소액 현금(카페·빵집용)', '일부 소규모 가게는 카드 최소 결제 금액이 있다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'IT'), 'PAYMENT', '소액 현금', '소도시 트라토리아·바는 현금만 받는 경우가 있다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'DE'), 'PAYMENT', '현지통화 현금 필수 수준', '현금 선호 문화가 강해 식당·카페에서 카드 거절되는 경우가 흔하다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'TR'), 'PAYMENT', '리라 현금(흥정용)', '그랜드 바자르 등 전통시장은 현금 흥정이 일반적이다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'CH'), 'PAYMENT', '소액 현금', '카드망은 잘 갖춰져 있으나 물가가 높아 예비 현금을 권장한다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'ID'), 'PAYMENT', '루피아 현금 다수 준비', '발리 관광지 외 지역은 카드 사용이 제한적이다. ATM 인출 수수료를 사전 확인한다.', 90),
((SELECT id FROM country WHERE iso_alpha2 = 'CZ'), 'PAYMENT', '소액 현금(구시가지 매대용)', '관광지 노점은 현금을 선호한다.', 90);