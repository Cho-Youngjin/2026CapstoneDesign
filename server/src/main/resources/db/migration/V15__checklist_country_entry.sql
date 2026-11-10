-- ============================================================
-- V15: 나라별 입국 서류 체크리스트
-- 출처 (2026-11 조회, 입국 규정은 자주 바뀌므로 출발 전 공식 사이트 재확인 필요)
--   일본  Visit Japan Web 등록 안내
--   태국  TDAC 안내 (tdac.info, 한국 여권 90일 무비자 기재)
--   필리핀 eTravel 등록 안내 (출발 72시간 전부터, 무료)
--   싱가포르 ICA 보도자료 (SG Arrival Card, 도착 전 3일 이내, 무료)
--   미국  ESTA (승인 시 2년, 처리 최대 72시간, 수수료 약 40달러대)
--   캐나다 IRCC eTA 안내 (7캐나다달러, 항공 입국)
--   유럽  EES 2026-04 전면 가동, ETIAS는 2027년 이후로 연기 (insideflyer.com)
--   대만  TWAC 안내 (도착 7일 전부터 제출 가능, 입국심사 전 필수)
--   중국  한국인 30일 무비자, 현재 공지 기준 2026-12-31까지 한시 (trip.com 가이드)
--   영국  주영국대사관 공지, 외교부 해외안전여행 (2026-01, 2026-10 공지, ETA 2026-02-25부터 의무)
--   호주  주한호주대사관 ETA 안내·FAQ, 외교부 해외안전여행 (2026-11 공지)
--   튀르키예 주이스탄불총영사관 안전여행 가이드북 (2026)
--   베트남 외교부 해외안전여행 공지 (2026-07-02, 사전입국신고 시범 확대)
--   인도네시아 트립닷컴 이용 가이드 (공식 사이트는 입국 전 입국 카드 작성만 확인, 3일 규정은 가이드 기준, 출발 전 재확인)
--   인도네시아 이민총국(imigrasi.go.id) VoA 대상 목록, B1 비자 안내 (비용·체류·신청 방법)
--   발리 관광세 발리 주정부 Love Bali 공식 사이트 (lovebali.baliprov.go.id)
--   홍콩  홍콩 입국사무처 방문비자 안내(immd.gov.hk), 외교부 해외안전여행 공지 (2026-04-16)
--
-- priority: 기존 같은 카테고리 항목 바로 뒤에 붙어야 앱에서 섹션이 반복되지 않는다.
--   DOCUMENT 75 (기존 60~74 뒤, MONEY 80 앞)
-- ============================================================

INSERT INTO checklist_template (country_id, category, title, description, priority) VALUES
((SELECT id FROM country WHERE iso_alpha2 = 'JP'), 'DOCUMENT', 'Visit Japan Web 등록', '입국심사·세관신고용 QR을 미리 발급. 항공편·숙소 확정 후 출국 전에 입력하고 스크린샷 저장.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'TH'), 'DOCUMENT', '태국 디지털 입국카드(TDAC) 제출', '도착 전 공식 정부 포털에서 무료로 제출하고 QR 저장. 한국 여권 무비자 체류는 90일(출발 전 재확인).', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'PH'), 'DOCUMENT', '필리핀 eTravel 등록', '출발 72시간 전부터 공식 사이트에서 무료 등록. 영문 항공권·숙소 바우처 필요, 영유아도 개별 등록.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'SG'), 'DOCUMENT', '싱가포르 SG Arrival Card 제출', '도착 3일 이내(당일 포함)에 ICA 사이트 또는 MyICA 앱에서 무료 제출. 유료 대행 사이트 주의.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'US'), 'DOCUMENT', 'ESTA 승인 받기', '출발 전 공식 사이트에서 신청. 처리 최대 72시간, 승인 시 보통 2년 유효, 새 여권이면 재신청. 대행 사이트 수수료 주의.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'CA'), 'DOCUMENT', '캐나다 eTA 신청', '항공 입국 시 필수. 공식 사이트에서 7캐나다달러, 대부분 몇 분 내 승인. 육로·해상 입국은 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'FR'), 'DOCUMENT', '여권 유효기간·EES 대비', '솅겐 입국은 여권 유효기간(출국 예정일 기준 3개월 이상) 확인. EES 생체 등록으로 입국 대기가 길 수 있고, ETIAS는 아직 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'IT'), 'DOCUMENT', '여권 유효기간·EES 대비', '솅겐 입국은 여권 유효기간(출국 예정일 기준 3개월 이상) 확인. EES 생체 등록으로 입국 대기가 길 수 있고, ETIAS는 아직 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'ES'), 'DOCUMENT', '여권 유효기간·EES 대비', '솅겐 입국은 여권 유효기간(출국 예정일 기준 3개월 이상) 확인. EES 생체 등록으로 입국 대기가 길 수 있고, ETIAS는 아직 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'DE'), 'DOCUMENT', '여권 유효기간·EES 대비', '솅겐 입국은 여권 유효기간(출국 예정일 기준 3개월 이상) 확인. EES 생체 등록으로 입국 대기가 길 수 있고, ETIAS는 아직 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'CH'), 'DOCUMENT', '여권 유효기간·EES 대비', '솅겐 입국은 여권 유효기간(출국 예정일 기준 3개월 이상) 확인. EES 생체 등록으로 입국 대기가 길 수 있고, ETIAS는 아직 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'CZ'), 'DOCUMENT', '여권 유효기간·EES 대비', '솅겐 입국은 여권 유효기간(출국 예정일 기준 3개월 이상) 확인. EES 생체 등록으로 입국 대기가 길 수 있고, ETIAS는 아직 불필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'TW'), 'DOCUMENT', '대만 온라인 입국카드(TWAC) 작성', '도착 7일 전부터 제출 가능하며 입국심사 전에 완료해야 함. 공식 포털에서 무료 작성.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'CN'), 'DOCUMENT', '중국 무비자 기간 확인', '한국 여권은 최대 30일 무비자이나 현재 공지 기준 2026-12-31까지 한시 시행. 연장 여부를 출발 전에 대사관 공지로 확인.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'GB'), 'DOCUMENT', '영국 ETA 신청', '출발 전 전자여행허가(ETA) 필수(경유도 해당). gov.uk 공식 사이트·앱에서만 신청, 수수료 20파운드, 유효 2년, 최대 3일 소요. 미취득 시 탑승 거부, 대행업체 과다 수수료 피해 주의.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'AU'), 'DOCUMENT', '호주 ETA 신청·여권 확인', '대한민국 여권 소지자는 최대 3개월 관광·방문·업무 목적 입국 시 Australian ETA 앱(무료 다운로드)에서 신청. 최소 여권 유효기간 규정은 없지만 항공사·환승국이 6개월 이상을 요구할 수 있어 확인.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'TR'), 'DOCUMENT', '튀르키예 여권 잔여기간·체류 확인', '입국 시 6개월 이상의 여권 잔여 유효기간 필요. 관광·단순 방문은 90일 무사증이며 과거 180일 중 90일 초과 불가(초과 시 벌금·입국 불가). 취업·사업 등은 비자 필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'VN'), 'DOCUMENT', '베트남 사전입국신고(PAI) 제출', '외국인 입국자 모두 대상(환승 제외). 입국 전 72시간 이내 권장, prearrival.immigration.gov.vn에서 온라인 작성 또는 QR 스캔. 공지(2026-07) 기준 호치민·푸꾸옥 공항은 의무, 다낭·깜라인·하노이는 시범 확대. 유사 사이트 주의.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'ID'), 'DOCUMENT', 'All Indonesia 전자입국카드 작성', '인도네시아 입국 전에 All Indonesia 사이트에서 입국 카드(세관신고 포함)를 작성. 입국 예정일 3일 이내부터 작성 가능, 동행은 그룹 신청(최대 10명). QR을 캡처해 두고 공항에서 제시. 발리 관광세는 별도 항목 참고.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'ID'), 'DOCUMENT', '인도네시아 도착비자(VoA) 준비', '한국은 도착비자(B1 관광) 대상. 비용 50만 루피아, 체류 30일(1회 연장 시 최대 60일). evisa.imigrasi.go.id에서 사전 신청하거나 도착 시 은행 창구에서 결제. 여권 잔여 6개월 이상, 왕복 또는 다음 목적지 항공권 필요.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'ID'), 'DOCUMENT', '발리 관광세 납부', '발리 방문 외국인은 관광세 1인당 15만 루피아를 납부. 발리 주정부 Love Bali 사이트(lovebali.baliprov.go.id)에서 방문 전 또는 체류 중 결제하고, 이메일로 받은 QR 바우처를 보관. 환율·카드 수수료로 실제 금액은 달라질 수 있음.', 75),
((SELECT id FROM country WHERE iso_alpha2 = 'HK'), 'DOCUMENT', '홍콩 무비자 90일·출국 항공권 확인', '한국 여권은 90일 무비자. 체류 기간을 감당할 충분한 자금과 홍콩을 떠나는 항공권을 소지. 입국이 보장되는 것은 아니며 무비자 상태의 불법 취업은 처벌(최대 징역 2년).', 75);

