# 해외여행 발걸음 (travel-footsteps)

Flutter + Spring Boot로 만든 **해외여행 준비·기록 Android 앱** (학부 캡스톤 / 4인 · 12주)

목적지 국가와 일정을 입력하면 외교부 공공데이터를 기반으로 **비자 요건을 판정하고 준비 일정을 역산**해 주고, 여행 중에는 **발걸음을 지도에 기록**하며 **일행과 위치를 공유**하고 **현지 언어를 번역**한다. 준비 단계부터 여행 중 활동까지를 앱 하나에서 처리하는 것이 목표다.

---

## 주요 기능

**필수 기능 6개**

| 기능 | 내용 |
|---|---|
| 비자 일정 & 알람 | 목적지·출발일·귀국일·여권 만료일을 입력하면 서버 규칙 엔진이 무비자 가능 여부와 여권 잔여 유효기간을 판정하고, D-90(여권 재발급) ~ D-7(최종 점검) 준비 일정을 역산해 로컬 알람으로 예약 |
| 국가별 준비물 체크리스트 | 플러그 타입·전압, 카드 통용도, 보조배터리 Wh 반입 규정, 유심/eSIM, 계절 의류를 국가 마스터 데이터로 자동 생성하고 체크 진행률 표시 |
| 맵 기반 발걸음 기록 | 세계지도에 방문국 채색 + 국가별 누적 걸음 수(상위) → 국가별 날짜순 체크인 핀 연결(하위). 수집은 WorkManager 1시간 주기 자동 · 수동 체크인 · Google Timeline 내보내기 JSON 임포트 3종 |
| 그룹 채팅 | 6자리 초대 코드로 여행 그룹 생성/참여, 그룹 채팅 + 1:1 DM, 사진·위치 메시지, 읽음 표시 |
| 실시간 위치 공유 | 앱 포그라운드에서 5초 간격 좌표를 STOMP로 전송 → 서버 메모리 릴레이 → 그룹원 지도에 마커 표시. 좌표는 저장하지 않으며 공유 ON/OFF 토글 상시 노출 |
| 번역 | 목적지 언어 자동 설정 + 텍스트 번역/상황별 문구 프리셋(입국심사·식당·교통·응급), 카메라 OCR 번역(온디바이스 ML Kit), 음성 양방향 번역(STT→번역→TTS) |

**확장 기능**

| 기능 | 내용 |
|---|---|
| 주변 여행 정보 | 현재 위치 기준 Google Places 검색(관광지·음식점·약국·ATM·숙소·편의점·마트·병원·미술관·놀이공원 10종) + 외교부 여행경보 1~4단계 배지 + 재외공관 연락처·위치 카드 |
| 환율 확인 + 경비 지갑 | 목적지 통화 기준 고시환율(한국수출입은행, 일 1회 서버 캐시)과 KRW 양방향 환산기, 카테고리별 경비 기록(기기 로컬 전용) |

**지원 국가** — 수집은 전 국가, 검증은 2티어로 나눈다. **Tier A(주요 20개국)** 는 수기 검증까지 마쳐 규칙 엔진이 완전 동작하고, **Tier B(나머지 전 국가)** 는 자동 수집만 하며 파싱에 실패하면 "영사관 확인 필요"로 안내한다. 검증되지 않은 데이터로 잘못된 비자 안내를 하지 않는 것이 원칙이다.

---

## 사용 기술

**앱 (Flutter / Android 전용)**

- Flutter 3.x · Dart (SDK ^3.13.2)
- Riverpod (상태관리), go_router (라우팅), dio (HTTP)
- drift / SQLite (로컬 DB)
- google_maps_flutter (지도), geolocator (위치), workmanager (백그라운드 수집)
- health → Health Connect (걸음 수)
- google_mlkit_text_recognition (OCR), speech_to_text · flutter_tts (음성) — 모두 온디바이스
- flutter_local_notifications (비자 알람), firebase_messaging (채팅 푸시)
- firebase_core · firebase_auth · google_sign_in

**서버 (Spring Boot)**

- Java 21 (Temurin) · Spring Boot 3.5.x
- Spring Web, Data JPA, Security, WebSocket(STOMP), Scheduler, Validation, Retry
- PostgreSQL 16 + Flyway (마이그레이션 V1~V8)
- Firebase Admin SDK 9.4.x (ID Token 검증)
- Lombok, Testcontainers (테스트)

**Firebase** — Auth(Google 로그인) · Firestore(채팅) · FCM(푸시) · Storage(사진)

**외부 데이터·API**

- 외교부 공공데이터(data.go.kr) — 입국허가요건, 여행경보, 재외공관
- 한국수출입은행 Open API — 고시환율
- Google Cloud Translation (NMT), Google Maps SDK, Places API

**배포·협업** — Oracle Cloud Always Free (ARM A1.Flex, Ubuntu 24.04) + Nginx 리버스 프록시 + systemd / GitHub Actions CI / GitHub Projects 칸반

---

## 실행 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.x stable (Dart SDK ^3.13.2) |
| JDK | Java 21 (Temurin) |
| 데이터베이스 | PostgreSQL 16 (서버 테스트는 Docker + Testcontainers 필요) |
| 개발 OS | Windows 11 / macOS / Linux |
| 빌드 대상 | Android (minSdk 23, applicationId `com.travelfootsteps.app`) — **iOS 미지원** |
| 서버 포트 | 8080 (에뮬레이터에서 로컬 서버 접속 시 호스트는 `10.0.2.2`) |
| 필요한 비밀 파일 | `app/android/app/google-services.json`, `server/firebase-service-account.json`, `server/.env` — 모두 `.gitignore` 대상이며 저장소에 포함되지 않음 |
| 필요한 외부 키 | data.go.kr 인증키, 한국수출입은행 API 키, Google Cloud (Translation / Maps / Places) 키 — 발급 절차는 `docs/setup-external-services.md` 참고 |

**권한** — 위치(백그라운드 포함), 카메라(OCR), 마이크(음성 번역), 알림, Health Connect 걸음 수 읽기. 백그라운드 발걸음 수집을 위해 첫 실행 시 배터리 최적화 예외를 한 번 요청한다.

---

## 주요 화면과 사용 흐름

로그인 후 하단 6개 탭으로 진입한다.

| 탭 | 화면 | 하는 일 |
|---|---|---|
| 비자 | 여행 계획 입력 → 판정 결과 | 목적지·출발일·귀국일·여권 만료일 입력 → 비자 판정 + 역산 일정 확인, 일정 항목 알람 예약 |
| 준비물 | 국가별 체크리스트 | 자동 생성된 준비물 항목 체크, 진행률 확인 |
| 발걸음 | 세계지도 → 국가 상세 | 방문국 채색·누적 걸음 수 확인, 국가 탭 → 날짜별 체크인 경로 확인, "여기 저장" 수동 체크인, Timeline JSON 임포트 |
| 그룹 | 그룹 목록 → 채팅방 / 위치공유 | 초대 코드로 그룹 생성·참여, 그룹 채팅·DM, 사진·위치 전송, 위치공유 ON/OFF |
| 번역 | 텍스트 / 카메라 / 음성 | 목적지 언어로 번역, 문구 프리셋 선택, 카메라로 메뉴판·표지판 OCR 번역, 마이크로 양방향 대화 번역 |
| 주변 | 지도 + 리스트 | 현재 위치 기준 카테고리별 장소 검색, 여행경보 배지·재외공관 카드 확인 |

**인증 흐름** — 앱이 Firebase Auth(Google)로 로그인해 ID Token을 받고, Spring 서버 호출에 `Authorization: Bearer <ID Token>`을 붙인다. 서버는 Firebase Admin SDK로 토큰을 검증해 `uid`만 사용한다. 자체 회원 테이블과 JWT 발급은 만들지 않는다.

---

## 프로젝트 구조

```text
travel-footsteps/
├─ app/                            # Flutter 앱 (Android 전용)
│  └─ lib/
│     ├─ main.dart, app.dart, router.dart   # 진입점 · go_router 6탭 + 로그인
│     ├─ core/auth/                # AuthRepository 추상화 + Firebase 구현체 + Riverpod provider
│     ├─ core/network/             # dio 기반 api_client (ID Token 인터셉터)
│     ├─ core/theme/               # 색상·텍스트 스타일·공통 위젯
│     └─ features/                 # visa, checklist, footsteps, group, translate, nearby, login
├─ server/                         # Spring Boot API 서버
│  └─ src/main/java/com/travelfootsteps/
│     ├─ auth/                     # TokenVerifier, FirebaseAuthFilter, SecurityConfig
│     ├─ country/ visa/ trip/      # 국가 마스터 · 비자 규칙 엔진 · 여행 계획
│     ├─ alert/ embassy/           # 여행경보 · 재외공관
│     ├─ batch/ externaldata/      # 공공데이터 수집 배치 · 자연어 요건 파서
│     ├─ places/ translate/        # 외부 API 프록시 (키를 APK 밖에 보관)
│     ├─ exchangerate/             # 고시환율 캐시
│     ├─ footsteps/ location/      # 체크인·걸음수 동기화 · STOMP 위치 릴레이
│     ├─ common/                   # HealthController 등
│     └─ resources/db/migration/   # Flyway V1~V8
├─ docs/
│  ├─ api-spec.md                  # REST / WebSocket API 명세
│  ├─ api-samples/                 # 공공데이터 응답 샘플
│  └─ superpowers/specs, plans/    # 설계 문서 · 태스크 단위 구현 계획
└─ .github/workflows/ci.yml        # flutter analyze + test, ./gradlew test
```

**브랜치 전략** — `main` / `develop` / `feature/*`. 모든 작업은 `feature/*`에서 시작해 `develop`으로 PR하며 2인 승인이 필요하다. 막판 통합을 피하기 위해 매주 금요일 `develop` 머지를 원칙으로 했다.

---

## 스크린샷 및 영상

<!-- TODO: 실행 화면 캡처와 시연 영상(GIF/링크)을 추가한다. -->

---

## 학습 포인트 / 구현 의도

- **자연어 데이터를 구조화하는 파서 설계** — 외교부 입국허가요건의 `gnrl_pspt_visa_cn` 필드는 "관광 목적 90일 무비자" 같은 자연어 문장이다. 이를 `{무비자여부, 허용일수, 여권잔여요건}`으로 정규화하는 배치 파서가 이 프로젝트의 핵심 구현물이고, 파싱에 실패했을 때 안전하게 degrade하는 설계(Tier A/B 분리)를 함께 연습했다.
- **백엔드 이원화 — 기술을 데이터 특성에 맞춰 고르기** — 오프라인 큐잉·메시지 순서·푸시가 기본 제공되는 영역(채팅·인증)은 Firebase에, 자연어 파싱·쿼터 관리·API 키 보호가 필요한 영역은 Spring Boot에 맡겼다.
- **실시간 기술 분리** — 영속화가 필요한 채팅은 Firestore, 5초 간격 고빈도 위치는 저장하지 않는 WebSocket(STOMP)으로 나눴다. 위치를 Firestore에 쓰면 사용자당 시간당 720 write로 무료 할당량이 즉시 소진된다.
- **인증 체계를 하나로 통일** — 자체 회원 테이블·비밀번호 해싱·JWT 발급을 만들지 않고 Firebase ID Token 하나를 두 백엔드가 공유한다. 로그인 수단이 늘어도 서버 코드는 바뀌지 않는다.
- **확장을 전제로 한 인터페이스 추상화** — 화면은 `AuthRepository`를, 서버는 `TokenVerifier`·번역 엔진 인터페이스를 경유한다. 덕분에 컨트롤러 테스트가 실제 Firebase를 호출하지 않고, 번역 엔진을 NMT에서 LLM 티어로 바꿔도 앱은 수정하지 않는다. Places 카테고리를 4종에서 10종으로 늘릴 때 enum 한 곳만 고치면 됐던 것도 같은 설계의 결과다.
- **배터리·비용 제약 안에서 타협점 찾기** — 발걸음 수집을 5초 간격 Foreground Service가 아닌 WorkManager 1시간 주기로 설계해 상주 알림 없이도 지도 표현에 충분한 데이터(하루 24건)를 확보했다. OCR·STT·TTS는 전부 온디바이스를 선택해 추가 비용을 0으로 만들었다.
- **API 키를 클라이언트 밖에 두기** — APK 디컴파일로 키가 추출되는 것을 막기 위해 Translation·Places 호출을 전부 서버 프록시로 경유시켰다.
- **4인 병렬 개발** — 기능을 화면부터 데이터까지 수직 슬라이스로 나눠 담당자별로 온전히 소유하게 하고, DB 스키마와 API 명세를 Phase 0에 먼저 확정해 병렬 작업의 전제를 만들었다.

---

## 현재 상태와 남은 작업

**완료**

- 필수 기능 6개(비자 판정·알람 / 준비물 / 발걸음 / 채팅 / 위치공유 / 번역)가 모두 동작한다.
- 서버: 공공데이터 배치 수집·정규화 파서, 비자 규칙 엔진, 번역·Places 프록시, 환율 캐시, 체크인·걸음수 동기화, STOMP 위치 릴레이, Flyway 스키마(V1~V8).
- Tier A 20개국 비자 데이터 수기 검증, Tier B 전 국가 자동 수집.
- Oracle Cloud Always Free VM에 서버 배포(Nginx 리버스 프록시 + systemd 자동 재시작), GitHub Actions CI(`flutter analyze`/`flutter test`, `./gradlew test`).
- 확장 기능: 주변정보(Places 10종 카테고리 + 여행경보 + 재외공관), 환율 확인 + 경비 지갑.

**남은 작업**

- HTTPS 전환 — 도메인이 없어 현재는 IP + HTTP로 접속하며, 앱에 `network_security_config.xml` 예외를 둔 상태다. 도메인을 확보하면 Nginx에 Let's Encrypt만 추가하면 된다(예외 설정은 그때 제거).
- CI/CD 자동 배포 — 현재 배포는 SSH 접속 후 `git pull && ./gradlew bootJar && systemctl restart` 수동 실행이다.
- 환전 알림(FCM 일 1회 푸시) 미구현.
- 이메일/비밀번호 회원가입 — Firebase Auth 내장 기능이라 화면 3개(가입/로그인/비밀번호 재설정) 추가로 가능하도록 설계만 해 둔 상태다. 추가 시 동일 이메일의 provider 충돌(`account-exists-with-different-credential`)을 `linkWithCredential`로 처리해야 한다.
- 방문 통계 대시보드 미구현.

**범위 밖 (v2 이후)** — iOS 지원, 낯선 사용자 매칭·오픈 채팅, 임의 파일 전송, 초 단위 이동 경로 추적, 비자 신청 대행·서류 업로드, 숙소·항공 예약 연동, 다인 정산(더치페이)·영수증 OCR, 스토어 배포.
