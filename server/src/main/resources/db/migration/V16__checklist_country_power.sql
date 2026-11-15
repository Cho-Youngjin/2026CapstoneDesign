-- V16: 나라별 전압·플러그 체크리스트 (POWER)
-- 전압·플러그는 잘 안 바뀌는 정보라 V15와 따로 추가함.
-- 값은 V9 country 테이블(plug_types, voltage_v) 기준이고, 한국 플러그(C형) 호환 여부는 일반 정보 기준.
-- priority 26: 기존 POWER(10/20/25) 바로 뒤, PAYMENT(30) 앞

INSERT INTO checklist_template (country_id, category, title, description, priority) VALUES
((SELECT id FROM country WHERE iso_alpha2 = 'JP'), 'POWER', '플러그·전압 확인 (A/B형, 100V)', 'A/B형 멀티어댑터 필요. 충전기는 대부분 100~240V 겸용이지만 220V 전용 드라이어 등은 사용 불가.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'VN'), 'POWER', '플러그·전압 확인 (220V)', '한국 플러그(C형)가 대부분 맞음. 호텔에 따라 A형 소켓이 있어 멀티어댑터를 챙기면 안전.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'TH'), 'POWER', '플러그·전압 확인 (220V)', 'A/B/C/O형이 모두 꽂히는 겸용 콘센트가 흔해 한국 플러그(C형)도 대부분 맞음. 겸용이 아닌 곳을 대비해 멀티어댑터 권장.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'US'), 'POWER', '플러그·전압 확인 (A/B형, 120V)', 'A/B형 어댑터 필요. 120V라 220V 전용 가전은 사용 불가, 스마트폰 충전기는 대부분 겸용.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'PH'), 'POWER', '플러그·전압 확인 (220V)', 'A/B/C형 혼용. 멀티어댑터를 챙기면 안전.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'CN'), 'POWER', '플러그·전압 확인 (220V)', '한국 플러그가 대부분 맞음. 소켓 형태가 다양해 멀티어댑터를 챙기면 안전.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'TW'), 'POWER', '플러그·전압 확인 (A/B형, 110V)', 'A/B형 어댑터 필요. 220V 전용 가전은 사용 불가.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'SG'), 'POWER', '플러그·전압 확인 (G형, 230V)', 'G형 어댑터 필요. 호텔에서 대여해 주는 경우도 있음.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'HK'), 'POWER', '플러그·전압 확인 (G형, 220V)', 'G형 어댑터 필요. 호텔에서 대여해 주는 경우도 있음.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'FR'), 'POWER', '플러그·전압 확인 (C/E형, 230V)', '한국 플러그(C형)를 그대로 사용 가능. 접지형(E) 소켓은 어댑터가 필요할 수 있음.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'IT'), 'POWER', '플러그·전압 확인 (C/F/L형, 230V)', '한국 플러그(C형)를 그대로 사용 가능.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'ES'), 'POWER', '플러그·전압 확인 (C/F형, 230V)', '한국 플러그(C형)를 그대로 사용 가능.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'DE'), 'POWER', '플러그·전압 확인 (C/F형, 230V)', '한국 플러그(C형)를 그대로 사용 가능.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'GB'), 'POWER', '플러그·전압 확인 (G형, 230V)', 'G형 어댑터 필요.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'AU'), 'POWER', '플러그·전압 확인 (I형, 230V)', 'I형 어댑터 필요.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'TR'), 'POWER', '플러그·전압 확인 (C/F형, 230V)', '한국 플러그(C형)를 그대로 사용 가능.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'CH'), 'POWER', '플러그·전압 확인 (C/J형, 230V)', '스위스 J형 소켓은 한국 플러그가 안 맞는 경우가 있어 스위스용 어댑터 권장.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'CZ'), 'POWER', '플러그·전압 확인 (C/E형, 230V)', '한국 플러그(C형)를 그대로 사용 가능.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'ID'), 'POWER', '플러그·전압 확인 (C/F형, 220~230V)', '한국 플러그(C형)를 그대로 사용 가능.', 26),
((SELECT id FROM country WHERE iso_alpha2 = 'CA'), 'POWER', '플러그·전압 확인 (A/B형, 120V)', 'A/B형 어댑터 필요. 220V 전용 가전은 사용 불가.', 26);
