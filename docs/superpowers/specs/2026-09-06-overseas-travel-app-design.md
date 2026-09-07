# 해외여행 발걸음 — 설계 문서

**작성일** 2026-09-06
**팀** 4인 (컴퓨터공학 3, IT 계열 1)
**기간** 12주
**성격** 학교 캡스톤 / 졸업작품

---

## 1. 개요

해외여행 준비부터 여행 중 활동까지를 하나로 묶는 Android 애플리케이션. 목적지 국가를 입력하면 비자 요건을 판정해 준비 일정을 역산해 주고, 여행 중에는 발걸음을 지도에 기록하며, 일행과 위치를 공유하고 현지 언어를 번역한다.

### 성공 기준

**필수 기능 6개가 모두 시연에서 동작하는 것.** 한 기능이 화려하고 다섯이 미완성인 상태가 가장 나쁜 결과다. 각 기능의 깊이는 과감하게 자르되 폭은 유지한다.

### 제약

- Android 전용 (iOS 미지원)
- 무료 티어 내에서 운영. GCP 예산 알림 $10 설정
- 실사용자 확보·스토어 배포는 범위 밖

---

## 2. 기술 스택

### 앱

| 영역 | 선택 |
|---|---|
| 프레임워크 | Flutter 3.x / Dart |
| 상태관리 | Riverpod |
| 라우팅 | go_router |
| 로컬 DB | drift (SQLite) |
| 지도 | google_maps_flutter |
| 위치 | geolocator |
| 백그라운드 | workmanager |
| 걸음 수 | health → Health Connect |
| OCR | google_mlkit_text_recognition (온디바이스·무료) |
| 음성 | speech_to_text, flutter_tts (온디바이스·무료) |
| 알림 | flutter_local_notifications (비자 알람), firebase_messaging (채팅 푸시) |
| HTTP | dio |

### 서버

Spring Boot 3.x / Java 21 — Web, Data JPA, Security, WebSocket(STOMP), Scheduler
PostgreSQL 16
Firebase Admin SDK (ID Token 검증)

### Firebase

Auth (Google 로그인) · Firestore (채팅) · FCM (푸시) · Storage (사진)

### 배포·협업

- Oracle Cloud Free Tier + Docker Compose (학교 서버가 있으면 우선)
- GitHub + GitHub Projects 칸반, PR 2인 승인
- GitHub Actions: `flutter analyze` + 테스트, `./gradlew test`
- 브랜치: `main` / `develop` / `feature/*`
- Figma (화면 설계), Discord/Notion (커뮤니케이션)

### 의도적으로 제외한 것

Redis(서버 인메모리 캐시로 충분), 자체 JWT 발급(Firebase 토큰 재사용), Kubernetes, 마이크로서비스.

---

## 3. 아키텍처

```
┌─────────────────────────────────────────────────┐
│           Flutter App (Android)                 │
│  ┌───────────┬───────────┬──────────────────┐   │
│  │ 비자/준비물 │ 발걸음/맵  │  그룹/채팅/번역   │   │
│  └───────────┴───────────┴──────────────────┘   │
└───────┬──────────────────────┬──────────────────┘
        │ Firebase SDK         │ REST / WebSocket
        ▼                      ▼
┌────────────────┐   ┌──────────────────────────────┐
│   Firebase     │   │   Spring Boot API 서버        │
│ ─────────────  │   │ ──────────────────────────── │
│ Auth (구글로그인)│◄──┤ ID Token 검증 (Admin SDK)     │
│ Firestore(채팅) │   │ 비자 규칙 엔진                 │
│ FCM (푸시)      │   │ 외부 API 프록시 (키 보호)      │
│ Storage (사진)  │   │ 공공데이터 배치 수집·정제       │
└────────────────┘   │ WebSocket 위치 릴레이 (STOMP)  │
                     └────────┬─────────────────────┘
                              │
                    ┌─────────┴──────────┐
                    │   PostgreSQL       │
                    │ 국가/비자/준비물     │
                    │ 여행일정/체크인      │
                    └────────────────────┘
                              ▲
                    ┌─────────┴──────────────────┐
                    │ 외교부 opendata (일 1회 배치)│
                    │ Google Translate / Places  │
                    └────────────────────────────┘
```

### 인증 흐름

두 백엔드를 잇는 핵심 고리다.

1. 앱이 Firebase Auth(Google)로 로그인 → **Firebase ID Token** 획득
2. Spring 서버 호출 시 `Authorization: Bearer <ID Token>` 첨부
3. 서버가 Firebase Admin SDK로 토큰 검증 → `uid` 추출

**자체 회원가입·비밀번호 관리를 만들지 않으면서 두 백엔드가 같은 사용자 신원을 공유한다.**

### 로그인 수단 확장 지점

v1은 Google 로그인만 제공하지만, **이메일/비밀번호 회원가입을 나중에 추가할 수 있게 설계한다.** Firebase Auth에 Email/Password provider가 내장돼 있어 콘솔 설정 + 화면 3개(가입 / 로그인 / 비밀번호 재설정)면 되고, **서버 코드는 변경되지 않는다.**

```
구글 로그인  ─┐
              ├─→ Firebase ID Token ─→ Spring 서버 (Admin SDK 검증)
이메일 가입  ─┘         (형태 동일)
```

서버는 토큰의 출처를 알 필요가 없다. 검증 후 `uid`만 사용한다.

**확장을 위해 v1부터 지켜야 할 규칙 4가지**

1. **`AuthRepository` 인터페이스로 추상화** — 화면이 `signInWithGoogle()`을 직접 호출하지 않고 repository를 경유한다. provider 추가가 repository 내부 변경으로 끝난다
2. **`uid` 외의 것에 의존하지 않는다** — 이메일 가입 사용자는 `displayName`·`photoUrl`이 없다. nullable로 처리하고 기본 아바타를 준비한다
3. **Firestore `users/{uid}` 문서를 로그인 방식과 무관하게 upsert** — 최초 로그인 시 uid 기준으로 생성한다
4. **이메일 인증(verification) 여부를 기능 접근 조건으로 삼지 않는다** — 나중에 켤 수 있도록 분리해 둔다

> **주의**: 동일 이메일로 Google 로그인과 이메일 가입을 모두 시도하면 Firebase가 `account-exists-with-different-credential` 오류를 낸다. `linkWithCredential`로 계정을 연결하는 처리가 필요하다.

자체 users 테이블 + 비밀번호 해싱 + JWT 직접 발급 방식은 채택하지 않는다. Firebase Auth와 인증 체계가 이중화되어 설계가 나빠진다.

### 백엔드를 둘로 나눈 근거

| Firebase가 맡는 것 | 이유 |
|---|---|
| 채팅, 푸시, 인증 | 오프라인 캐시·메시지 순서·영속화가 기본 제공. 직접 만들면 오프라인 큐잉·재연결·읽음 처리를 전부 구현해야 함 |

| Spring이 맡는 것 | 이유 |
|---|---|
| 공공데이터 수집·정규화 | 원본이 자연어 텍스트라 파싱이 필요하고, API 호출 한도(일 10,000회)를 앱이 직접 쓰면 초과 |
| 비자 규칙 엔진 | 규칙을 DB에 두면 앱 재배포 없이 갱신 가능 |
| 외부 API 프록시 | APK 디컴파일로 API 키가 추출되는 것을 방지. 번역 엔진 교체도 서버 설정만으로 가능 |
| 실시간 위치 릴레이 | 5초 간격 좌표를 Firestore에 쓰면 write 비용이 폭증 (사용자당 시간당 720 write) |

**실시간 기술을 데이터 특성에 따라 나눴다.**

| | 채팅 | 실시간 위치 |
|---|---|---|
| 영속화 | 필요 | 불필요 |
| 오프라인 전달 | 필요 | 불필요 |
| 푸시 알림 | 필요 | 불필요 |
| 갱신 빈도 | 낮음 | 높음 (5초) |
| **선택** | **Firestore** | **WebSocket(STOMP)** |

---

## 4. 외부 데이터 소스 (검증 완료)

### 외교부 공공데이터 — REST + JSON, 무료, 이용허락범위 제한 없음

| 데이터셋 | 용도 | URL |
|---|---|---|
| 국가·지역별 입국허가요건 | 비자 판정 핵심 소스 | data.go.kr/data/15075345 |
| 국가·지역별 여행경보 | 1~4단계 경보 | data.go.kr/data/15076237 |
| 국가·지역별 재외공관 정보 | 위도·경도 포함, 지도 핀 | data.go.kr/data/15075354 |
| 여행경보 히스토리 | 통계 | data.go.kr/data/15059195 |

**입국허가요건 API 스펙**
- 요청: `serviceKey`, `numOfRows`, `pageNo`, `cond[country_iso_alp2::EQ]`, `returnType`
- 응답 필드: `country_nm`, `country_eng_nm`, `country_iso_alp2`, `gnrl_pspt_visa_yn`/`gnrl_pspt_visa_cn`(일반여권), `ofclpspt_visa_yn`/`cn`(관용여권), `dplmt_pspt_visa_yn`/`cn`(외교관여권), `nvisa_entry_evdc_cn`(무비자 근거), `remark`
- 인증키 필수. 개발계정 **일 10,000회** 자동승인, 운영계정은 심사

> **핵심 제약**: `gnrl_pspt_visa_cn`은 *"관광 목적 90일 무비자"* 같은 **자연어 문장**이다. 구조화된 숫자가 아니므로 규칙 엔진을 돌리려면 `{무비자여부, 허용일수, 여권잔여요건}`으로 정규화하는 파서가 필요하다. **이 파서가 서버 배치 작업의 실질적 내용이자 이 프로젝트의 핵심 구현물이다.**

**활용신청은 W1 첫 작업으로 즉시 진행한다.**

### 한국수출입은행 Open API — 환율 (T3)

REST + JSON, 무료, 일 1,000회. 매일 영업일 고시환율(매매기준율)을 국가 통화 코드로 조회. 서버가 하루 한 번 배치로 캐싱해 두면 앱은 서버 API만 호출하면 된다. `data.go.kr`이 아니라 한국수출입은행 자체 Open API(`https://oapi.koreaexim.go.kr`)에서 발급.

### Google Cloud Translation

| 옵션 | 가격 | 무료 티어 |
|---|---|---|
| Basic v2 / Advanced v3 NMT | $20 / 100만 자 | **월 50만 자** ($10 크레딧) |
| Text Translation (LLM) | $10 입력 + $10 출력 / 100만 자 | — |
| Adaptive MT (LLM) | $25 + $25 / 100만 자 | — |

**NMT를 기본값으로 시작하고, 번역 엔진을 서버 인터페이스 뒤에 추상화한다.** 문맥 품질이 필요한 지점(OCR로 읽은 메뉴판 등)은 나중에 LLM 티어로 앱 수정 없이 교체할 수 있게 한다. Gemini API 직접 호출도 같은 인터페이스로 교체 가능한 선택지로 열어 둔다.

### 기타

- Google Maps SDK (지도), Places API (주변 정보)
- Health Connect (걸음 수, 온디바이스·무료)
- ML Kit Text Recognition, 온디바이스 STT/TTS (무료)

---

## 5. 지원 국가 범위

수집과 검증을 분리한다. 스키마와 수집 파이프라인은 **처음부터 전 국가**를 다룬다.

| | 대상 | 데이터 | 비자 알람 |
|---|---|---|---|
| **Tier A** | 주요 20개국 | 공공데이터 + 수기 검증 | 규칙 엔진 완전 동작 |
| **Tier B** | 나머지 전 국가 | 공공데이터 자동 수집 | 규칙 파싱 성공 시 동작, 실패 시 "영사관 확인 필요" 안내 |

**Tier A 20개국**: 일본, 베트남, 태국, 미국, 필리핀, 중국, 대만, 싱가포르, 홍콩, 프랑스, 이탈리아, 스페인, 독일, 영국, 호주, 튀르키예, 스위스, 체코, 인도네시아, 캐나다

규칙 엔진은 데이터가 없을 때 안전하게 degrade한다. 검증되지 않은 데이터로 잘못된 비자 안내를 하지 않는 것이 원칙이다.

---

## 6. 기능 명세

### 우선순위 티어

일정 압박 시 판단 기준. 아래 일정표의 T1/T2/T3는 이 구분을 가리킨다.

| 티어 | 기능 |
|---|---|
| **T1 — 반드시** | ① 비자 규칙+알람 · ② 준비물 · ③ 발걸음(백그라운드+임포트) |
| **T2 — 반드시** | ④ 그룹/DM/사진/읽음 · ⑤ 텍스트+OCR+음성 번역 |
| **T3 — 여유 시** | ⑥ 주변정보 심화 · 통계 대시보드 · **이메일/비밀번호 회원가입** · **⑦ 환율 확인 + 경비 지갑** |

⑥의 기본형은 T2에 포함되며, 심화만 T3다. Places API 호출이라 가장 적은 노력으로 화면이 채워지므로 시연 분량이 필요할 때 가성비가 좋다.

### ① 비자 일정 & 알람 — 핵심 기능

사용자가 여행 계획(목적지, 출발일, 귀국일, 여권 만료일)을 입력하면 서버 규칙 엔진이 판정하고 준비 일정을 역산한다.

```
입력: 베트남 / 2026-12-20 출발 / 20일 체류 / 여권만료 2027-03-15
          ↓ 규칙 엔진
판정: ⚠️ 무비자 45일 이내 → 체류일수 OK
      ❌ 여권 잔여유효기간 85일 → 6개월 요건 미달, 재발급 필요

역산 일정:
  D-90 (09/21)  여권 재발급 신청     🔔
  D-45 (11/05)  항공권·숙소 확정      🔔
  D-30 (11/20)  여행자보험 가입       🔔
  D-7  (12/13)  최종 서류 점검        🔔
```

**판정 로직**

```
입력: countryIso, departDate, returnDate, passportExpiry

1. visa_requirement 조회 (passport_type = GENERAL)
2. stayDays = returnDate - departDate
3. 비자 판정
   - visa_free_days == null            → "영사관 확인 필요" (Tier B 미검증)
   - visa_required == false
       && stayDays <= visa_free_days   → 무비자 가능
   - visa_required == false
       && stayDays >  visa_free_days   → 비자 필요 (무비자 체류 초과)
   - visa_required == true             → 비자 필요
4. 여권 판정
   - (passportExpiry - returnDate) >= passport_validity_months → OK
   - 미달 → 재발급 필요
5. 역산 일정 생성 (departDate 기준, 조건부 항목 포함)
   D-90 여권 재발급        ← 여권 판정 실패 시에만
   D-45 비자 신청          ← 비자 필요 시에만
   D-30 항공권·숙소 확정, 여행자보험
   D-14 준비물 구매
   D-7  최종 점검
   → 이미 지난 날짜의 항목은 "지금 바로" 로 표시
```

각 항목은 `flutter_local_notifications`로 로컬 알람을 예약한다. **서버 푸시가 필요 없다** — 사용자 본인의 일정이므로.

**제외**: 비자 신청 대행, 서류 업로드, 영사관 예약 연동

### ② 국가별 준비물 체크리스트

국가 마스터 데이터로 자동 생성, 사용자가 체크하면 진행률 표시.
플러그 타입(예: C형 220V) · 결제수단(카드 통용도, 현금 권장) · 보조배터리 반입 규정(Wh 제한) · 유심/eSIM · 계절 의류

**제외**: 쇼핑몰 연동, 무게·부피 계산, 짐 사진 관리

### ③ 맵 기반 발걸음 기록

**2단 지도 구조**
- 상위: 세계지도에 방문국 채색 + 국가별 누적 걸음 수
- 하위: 국가 탭 → 날짜별 체크인 핀을 시간순 점선으로 연결

**수집 방식 3종**

| 방식 | 내용 |
|---|---|
| 백그라운드 자동 (메인) | **WorkManager 1시간 주기**로 좌표 1건 기록 |
| 포그라운드 수동 | "여기 저장" 버튼 |
| Timeline 임포트 (보조) | Google Maps 타임라인 내보내기 JSON을 `file_picker`로 받아 파싱 |

걸음 수는 Health Connect에서 일별로 읽어 그날의 국가에 귀속시킨다.

> **1시간 간격을 택한 이유**: 배터리 문제의 근원은 고빈도 GPS다. 5초 간격은 Foreground Service + 상주 알림이 필요하고 제조사 배터리 최적화에 죽지만, 1시간 간격은 WorkManager 주기 작업으로 충분하고 상주 알림도 불필요하며 하루 데이터가 24건이라 지도에 그리기 적당하다. Doze 모드에서 정확히 1시간이 아니라 "대략 1시간"으로 밀리지만 무해하다. 첫 실행 시 배터리 최적화 예외를 한 번 요청한다.

> **Google Timeline API는 존재하지 않는다.** Google은 Timeline을 기기 로컬 저장으로 전환했고 제3자 앱이 프로그래매틱하게 읽을 공개 API가 없다. 수동 내보내기 파일을 파싱하는 것만 가능하므로 보조 수단으로만 쓴다. 다만 앱 설치 이전의 과거 기록을 채울 수 있어 시연에서 빈 지도로 시작하지 않아도 된다.

### ④ 그룹 위치 공유 + 채팅

- 6자리 **초대 코드**로 여행 그룹 생성/참여 → 동의가 명시적이므로 프라이버시 설계가 단순하다
- **채팅**: 그룹 채팅 + 1:1 DM. 사진 전송(Firebase Storage), 위치 공유 메시지, 읽음 표시
- **읽음 표시**: 메시지마다 쓰지 않고 **채팅방 문서에 사용자별 `lastReadAt` 타임스탬프**만 저장 → write 횟수 1/N, 안 읽은 개수 계산 가능
- **실시간 위치**: 앱 포그라운드일 때 5초마다 STOMP 송신 → 서버 메모리 릴레이 → 그룹원 지도에 마커. **저장하지 않음**
- **위치 공유 ON/OFF 토글 상시 노출**

**제외**: 임의 파일 전송(확장자 처리·미리보기·용량 제한 등 부수 작업 대비 시연 임팩트가 사진과 동일), 낯선 사용자 매칭

### ⑤ 번역

- 목적지 국가 언어를 기본값으로 자동 설정
- **텍스트 번역** + 상황별 문구 프리셋(입국심사 / 식당 / 교통 / 응급)
- **카메라 OCR 번역**: ML Kit Text Recognition(온디바이스) → 텍스트 추출 → 번역 API
- **음성 번역**: `speech_to_text` → 번역 → `flutter_tts`로 읽어주기 (양방향 대화 모드)
- 모든 번역 호출은 서버 프록시 경유

OCR·STT·TTS가 모두 온디바이스라 **추가 비용이 발생하지 않는다.**

### ⑥ 주변 여행 정보 (기본형)

현재 위치 기준 Google Places 검색(관광지·음식점·약국·ATM) + 외교부 여행경보 단계 + 재외공관 연락처·위치. 지도와 리스트를 동시 제공한다.

**제외**: 리뷰·평점 작성, 예약, 일정 자동 추천

### ⑦ 환율 확인 + 경비 지갑 (T3 — 필수 6개 외 확장)

목적지 통화 기준 오늘의 환율을 보여주고, 아직 환전 전이면 하루 한 번 푸시로 알려준다. 여행 중 쓴 돈을 간단히 기록하는 지갑을 곁들인다.

- **환율 표시**: `trip`에 저장된 목적지 통화로 서버 캐시 환율(한국수출입은행 고시환율, 일 1회 갱신) 조회. KRW ↔ 현지통화 양방향 환산기
- **환전 알림**: 여행 `trip_task`에 "환전" 체크 항목을 두고, 미체크 && D-14 이내면 매일 오전 1회 FCM 푸시로 "오늘 환율 OOO원" 알림. 체크되면 알림 중단
- **경비 지갑**: 로컬 전용(서버 저장 없음, drift). 카테고리(식비/교통/숙박/쇼핑/기타) + 금액(현지통화, KRW 환산은 그날 환율로 표시) + 메모. 여행별 합계만 보여주는 단순 리스트 — 예산 설정, 정산, 영수증 사진은 하지 않는다

**제외**: 다인 정산(더치페이 계산), 예산 초과 경고, 영수증 OCR, 서버 동기화(기기 변경 시 유실 감수)

---

## 7. 데이터 모델

### PostgreSQL

```
country
  id, iso_alpha2, iso_alpha3, name_ko, name_en, continent, tier(A|B),
  plug_types, voltage_v, frequency_hz, currency_code,
  card_acceptance(HIGH|MEDIUM|LOW), power_bank_wh_limit, updated_at

visa_requirement
  id, country_id, passport_type(GENERAL|OFFICIAL|DIPLOMATIC),
  visa_required(bool), visa_free_days(int, null 가능),
  passport_validity_months(int, null 가능),
  raw_text, evidence_text, remark,
  source_fetched_at, verified(bool)      ← Tier A 수기 검증 여부

travel_alert    country_id, level(1~4), region, title, issued_at
embassy         country_id, type, name, lat, lng, phone, emergency_phone, address
checklist_template  id, country_id(null=공통), category, title, description, priority

trip            id, firebase_uid, country_id, depart_date, return_date,
                passport_expiry, created_at
trip_task       id, trip_id, title, due_date, done, notification_id
trip_checklist  id, trip_id, template_id, checked

checkin         id, firebase_uid, lat, lng, country_id, recorded_at,
                source(AUTO|MANUAL|IMPORT)
daily_steps     id, firebase_uid, date, country_id, step_count

exchange_rate   id, currency_code, krw_rate, base_date   ← 일 1회 배치 갱신 (T3)
```

### 로컬 전용 (drift, 서버 미저장)

```
wallet_entry    id, trip_id, category, amount_local, memo, spent_at   ← 경비 지갑 (T3)
```

### Firestore

```
users/{uid}
  displayName, photoUrl, fcmToken

rooms/{roomId}
  type(GROUP|DM), name, inviteCode, participants[],
  lastMessage, lastMessageAt, lastReadAt{uid: timestamp}

rooms/{roomId}/messages/{msgId}
  senderUid, type(TEXT|IMAGE|LOCATION),
  text, imageUrl, lat, lng, createdAt
```

### 주요 API

```
GET  /api/countries                        국가 목록
GET  /api/countries/{iso2}                 국가 상세 (준비물 포함)
GET  /api/countries/{iso2}/checklist       준비물 템플릿
GET  /api/countries/{iso2}/alerts          여행경보
GET  /api/countries/{iso2}/embassies       재외공관

POST /api/trips                            여행 생성 → 비자 판정 + 역산 일정 반환
GET  /api/trips/{id}
POST /api/trips/{id}/tasks/{taskId}/done

POST /api/translate                        번역 프록시
GET  /api/places/nearby                    Places 프록시
GET  /api/exchange-rates/{currencyCode}    캐시된 환율 (T3)

WS   /ws  (STOMP)
  SEND      /app/location            {roomId, lat, lng, ts}
  SUBSCRIBE /topic/group/{roomId}/location
```

---

## 8. 역할 분담

4명을 **수직 슬라이스**로 나눈다. 각자 화면부터 데이터까지 한 기능을 온전히 소유해 "누가 안 끝내서 내가 못 한다"는 상황을 최소화한다.

| | 담당 | 주요 산출물 |
|---|---|---|
| **R1** 백엔드 | Spring Boot 전체 | 공공데이터 배치 수집·**정규화 파서**, 비자 규칙 엔진, 번역/Places 프록시, WebSocket 위치 릴레이, DB 스키마, 배포·CI |
| **R2** 앱 코어 | Flutter 기반 + ①비자 + ④채팅 | 앱 아키텍처(라우팅/상태관리/네트워크 계층), Firebase 인증, 여행계획 CRUD, 비자 결과 화면, 로컬 알람, Firestore 채팅(그룹→DM→사진→읽음) |
| **R3** 지도·센서 | ③발걸음 + ⑥주변정보 | 2단 지도, Health Connect, WorkManager 백그라운드 추적, Timeline 임포트, 위치공유 클라이언트, Places·여행경보·공관 화면 |
| **R4** 번역·데이터 | ⑤번역 + ②준비물 | 번역 3종(텍스트/OCR/음성), 문구 프리셋, 준비물 체크리스트, 공통 UI 컴포넌트·디자인 시스템, Tier A 20개국 데이터 검증, 문서·발표자료·QA |

**R4를 경험이 적은 팀원에게 배정한다.** 번역은 패키지 조합 성격이라 서버 통신이나 복잡한 상태관리가 적고, 데모 임팩트는 가장 크며(메뉴판 OCR 번역), 공통 UI 컴포넌트를 맡으면 자연스럽게 전체 코드베이스를 읽게 된다.

**보완책**: 주 1회 페어 프로그래밍 세션 고정. OCR은 W9에 배치해 앞에서 Flutter에 익숙해질 시간을 준다.

**R2가 가장 무겁다.** 앱 코어는 초반 집중, 채팅은 중반이라 시간상 분산되지만 경험이 가장 많은 사람이 맡는다.

---

## 9. 일정표 (12주)

### Phase 0 — W1~2 · 기반 구축 (전원 공동)

- **[즉시] 공공데이터포털 활용신청** — 미루면 W3에 막힌다
- GCP 결제계정 + Maps/Translation 키, **예산 알림 $10 설정**
- Firebase 프로젝트, GitHub 저장소 + Actions + 브랜치 규칙
- Figma 전 화면 와이어프레임
- **DB 스키마 + API 명세 초안 확정** ← 병렬 작업의 전제
- Flutter 스켈레톤 + Firebase Auth 로그인

> **M1 게이트 (W2말)** — 로그인 후 6개 탭을 빈 화면으로 이동할 수 있다

### Phase 1 — W3~5 · 데이터 파이프라인 + T1 기초

| R1 | R2 | R3 | R4 |
|---|---|---|---|
| 배치 수집기, **입국허가요건 파서**, 국가 마스터 API | 여행계획 CRUD, 비자 결과 화면 | 2단 지도, Health Connect 걸음 읽기 | 준비물 체크리스트, 공통 UI 컴포넌트 |

> **M2 게이트 (W5말)** — 목적지를 입력하면 비자 판정 + 준비물 목록이 표시된다

### Phase 2 — W6~8 · T1 완성 + T2 착수

| R1 | R2 | R3 | R4 |
|---|---|---|---|
| 비자 규칙 엔진(역산 일정), 번역 프록시, WebSocket 릴레이 | 로컬 알람 예약, 그룹 채팅 → DM | **WorkManager 백그라운드 추적**, Timeline 임포트, 위치공유 클라이언트 | 텍스트 번역, 문구 프리셋 |

> **M3 게이트 (W8말)** — 6개 기능이 전부 기본 형태로 동작한다 **(가장 중요한 게이트)**

### Phase 3 — W9~10 · 확장 + 통합

| R1 | R2 | R3 | R4 |
|---|---|---|---|
| 배포 안정화, Tier B 전 국가 수집 | 사진 전송, 읽음 표시 | 주변정보(Places+경보+공관) | **OCR 번역, 음성 번역** |

W10 후반은 전원 통합 테스트 주간.

### Phase 4 — W11 · 안정화

실기기 테스트(제조사별 최소 3종), 배터리 최적화 예외 플로우, 권한 요청 시퀀스 점검, 버그 수정. 데모 시나리오 확정 + 리허설 2회. 시연용 시드 데이터 준비.

### Phase 5 — W12 · 마감

발표자료, 시연 영상, 최종 보고서, 코드 정리·README.

---

## 10. 리스크 & 대응

| 리스크 | 대응 |
|---|---|
| 공공데이터 자연어 파싱 실패율이 높음 | **W3 조기 착수.** Tier A 20개국은 수기 보정으로 확실히 커버 |
| 백그라운드 추적이 기기마다 다르게 죽음 | W6 착수로 디버깅 시간 확보. 최악의 경우 **포그라운드 체크인 + Timeline 임포트로 대체** — 백업 경로가 설계에 이미 있음 |
| API 과금 폭주 | 예산 알림 $10, 서버단 캐시, GCP 쿼터 상한 설정 |
| R4 병목 | 주 1회 페어링 고정, OCR은 W9 배치 |
| 막판 통합 지옥 | **매주 금요일 `develop` 머지 필수.** 통합을 W10에 몰지 않는다 |
| 공공데이터 운영계정 심사 지연 | 개발계정(일 10,000회, 자동승인)으로 전 기간 진행 가능. 운영계정은 여유 있게 신청 |
| 이메일 가입 추가 시 계정 충돌 | 동일 이메일의 Google/이메일 provider 충돌(`account-exists-with-different-credential`)을 `linkWithCredential`로 처리. 시연 중 재현되기 쉬운 지점이므로 T3 착수 시 우선 확인 |

### 여유가 없어질 때 자르는 순서

1. ⑦ 환율/지갑, ⑥ 주변정보 심화
2. 음성 번역
3. 사진 전송
4. 읽음 표시

위에서부터 자른다.

---

## 11. 범위 밖 (v2 이후)

- iOS 지원
- 낯선 사용자 매칭 / 오픈 채팅
- 임의 파일 전송
- 고빈도(초 단위) 이동 경로 추적
- 비자 신청 대행, 서류 업로드, 영사관 예약
- 숙소·항공 예약 연동, 일정 자동 추천
- 다인 정산(더치페이), 예산 초과 경고, 영수증 OCR (경비 지갑은 T3로 기본형만 포함)

---

## 12. 결정 기록

| 결정 | 근거 |
|---|---|
| Flutter + Android 전용 | Health Connect가 Android 전용. iOS는 HealthKit 별도 구현이라 3개월에 불가 |
| Firebase + Spring 하이브리드 | 채팅의 어려운 부분(오프라인 큐잉·푸시·순서)은 Firebase가 해결, 서버는 데이터 정규화·규칙·프록시라는 실질적 책임을 가짐 |
| 채팅=Firestore, 위치=WebSocket | 영속화 필요 여부와 갱신 빈도가 정반대. 위치를 Firestore에 쓰면 무료 할당량이 한 시간에 소진 |
| 자체 JWT 미발급 | Firebase ID Token을 서버가 검증. 회원 관리 구현 불필요. 로그인 수단을 추가해도 토큰 형태가 같아 **서버 코드가 변경되지 않는다** |
| v1은 Google 로그인만 | 이메일/비밀번호는 Firebase Auth 내장 기능이라 T3에서 화면 3개만 추가하면 된다. 확장 규칙 4가지를 v1부터 지켜 나중에 화면을 뜯어고치지 않도록 한다 |
| 백그라운드 추적 1시간 간격 | 배터리·권한 문제의 근원인 고빈도 GPS를 회피하면서 지도 표현에 충분한 데이터 확보 |
| 국가 2티어 | 전 국가를 수집하되 20개국만 검증. 미검증 데이터로 잘못된 비자 안내를 하지 않음 |
| 번역 NMT 기본 + 인터페이스 추상화 | 월 50만 자 무료로 시연 충분. LLM 티어·Gemini API로 앱 수정 없이 교체 가능 |
| 환율/지갑을 T3로, 지갑은 로컬 전용 | 필수 6개 기능에 영향 없이 시연 임팩트를 추가. 지갑은 서버 동기화·정산 없이 drift만으로 구현되므로 R2/R4 여유 시간에 소화 가능 |
