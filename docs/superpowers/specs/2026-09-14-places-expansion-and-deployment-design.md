# Places 카테고리 확장 + 서버 배포 — Design

**작성일**: 2026-09-14
**배경**: Plan A(서버) 완료 후, 배포 전에 처리하기로 한 두 가지 작은 개선. 환전 알림(FCM) 기능은 별도 후속 브레인스토밍으로 미룬다(스코프 밖).

## 1. Places 카테고리 확장

### 목표
`GET /api/places/nearby`가 지원하는 카테고리를 4개(관광지/음식점/약국/ATM)에서 10개로 늘린다.

### 추가할 카테고리
| 앱 카테고리 | Google Places `type` |
|---|---|
| `LODGING` | `lodging` |
| `CONVENIENCE_STORE` | `convenience_store` |
| `SUPERMARKET` | `supermarket` |
| `HOSPITAL` | `hospital` |
| `MUSEUM` | `museum` |
| `AMUSEMENT_PARK` | `amusement_park` |

편의점과 마트는 구글 `type`이 서로 달라서(현재 아키텍처가 "카테고리 하나 = 구글 type 하나"로 1:1 매핑) 두 개로 나눈다. 관광지도 기존 `TOURIST`(광범위)는 그대로 두고, 미술관·놀이공원을 별도 카테고리로 추가한다(서로 겹치는 결과가 나와도 무방 — 필터는 원래 상호 배타적이지 않다).

### 변경 범위
- `server/src/main/java/com/travelfootsteps/places/PlaceCategory.java`에 enum 상수 6개 추가. 그 외 컨트롤러(`PlacesController`)·DTO(`PlaceResponse`)·클라이언트(`GooglePlacesClient`)는 전부 이 enum을 통해 동작하므로 **코드 변경 없음** — enum이 이 프로젝트가 의도한 대로 "매핑 한 곳만 고치면 되는" 확장점 역할을 한다.
- 테스트: `GooglePlacesClientTest`에 신규 카테고리 1개(예: `LODGING`) 왕복 검증 추가, `PlacesControllerTest`에 신규 카테고리로 호출했을 때 400이 아니라 정상 처리되는지 확인하는 케이스 추가.

### 스코프 밖
- 앱(Flutter, Plan F)의 필터 탭 UI에 새 카테고리 6개를 반영하는 작업은 이 설계에 포함하지 않는다 — Plan F 담당자가 이 API 변경을 반영해 진행한다. (참고로 10개 탭이 한 줄에 다 안 들어갈 수 있어 가로 스크롤 등 레이아웃 처리가 필요할 수 있음 — Plan F 쪽 UI 판단.)

---

## 2. 서버 배포 — Oracle Cloud Always Free

### 목표
지금까지 로컬에서만 실행되던 Spring Boot 서버를, 팀원들의 앱이 실제로 호출할 수 있는 상시 접근 가능한 URL로 배포한다.

### 플랫폼 선택 근거
Railway(실질 월 $5), Render(무료 DB가 30일+14일 유예 후 자동 삭제), AWS(2025년 7월 이후 신규 계정은 $100 크레딧 6개월 한정, 만료 후 경고 없이 자동 과금)를 비교한 결과, **Oracle Cloud Always Free**만 시간 제한·자동 유료 전환·데이터 삭제 위험이 전혀 없다. 대신 관리형 플랫폼(Railway 등)과 달리 VM을 직접 운영해야 하는 부담이 있다.

### 인프라 구성
- **인스턴스**: `VM.Standard.A1.Flex`(ARM Ampere), 2 OCPU / 12GB RAM, Ubuntu 24.04 — Always Free 한도(최대 4 OCPU/24GB) 안에서 여유 있게 잡는다. Postgres와 Spring Boot를 같은 VM에서 함께 돌리기에 충분하다.
- **소프트웨어 스택**: Java 21(Temurin, apt), PostgreSQL 16(apt, 로컬호스트에만 바인딩 — 외부 노출 안 함), Nginx(80번 포트에서 Spring Boot 8080번으로 리버스 프록시).
- **프로세스 관리**: Spring Boot jar를 systemd 서비스로 등록 — VM 재부팅이나 크래시 시 자동 재시작.
- **네트워크 보안**: Oracle Cloud Security List에서 **80(HTTP), 22(SSH)만** 인그레스 허용. 8080(앱 직접), 5432(Postgres)는 외부에 절대 안 연다 — Nginx만 외부 접점이 되고 나머지는 로컬호스트 통신.
- **HTTPS**: 지금은 안 함(도메인이 없어서). IP로 HTTP 직접 접속. 나중에 도메인 생기면 Nginx에 Let's Encrypt(Certbot)만 추가하면 되는 구조로 미리 짜둔다(Nginx를 처음부터 리버스 프록시로 둔 이유).

### 비밀정보 전달
`server/.env`(3개 API 키 + DB 접속정보)와 `firebase-service-account.json`은 git에 올라간 적 없는 로컬 파일이므로, VM 프로비저닝 후 `scp`로 1회 직접 전송한다. 이후 코드 갱신은 git pull로만 하고, 이 두 파일은 VM에 그대로 둔다(재전송 불필요).

### 배포 프로세스 (수동, MVP)
1. VM에서 저장소 clone
2. `.env`/`firebase-service-account.json` scp로 배치
3. `./gradlew bootJar`
4. systemd 서비스 등록 후 시작
5. 이후 갱신: `git pull && ./gradlew bootJar && sudo systemctl restart travel-footsteps-server` (수동 SSH 실행)

CI/CD 자동 배포(GitHub Actions → SSH deploy)는 이번 스코프에서 제외한다 — 지금은 배포 자체를 먼저 성립시키는 게 우선이고, 자동화는 팀이 배포를 자주 반복하게 되면 그때 별도로 추가한다(YAGNI).

### 앱(Flutter) 쪽 연동
Android는 기본적으로 평문 HTTP 호출을 차단한다. `network_security_config.xml`에 **이 서버의 IP 주소 하나만** 예외로 허용하는 설정을 추가해야 한다(전역 허용 아님 — 이 서버로 가는 트래픽만). 이 부분은 앱 담당 팀원 작업이며, 서버 배포가 끝나 IP가 확정되면 그 값을 전달한다. 도메인+HTTPS로 전환되면 이 예외 설정은 제거한다.

### 검증 계획
배포 직후: `GET /api/health`(무인증)로 생존 확인 → 실제 Firebase ID 토큰으로 `GET /api/countries`(인증 필요) 호출해 Firebase Admin SDK 연동과 Flyway 마이그레이션이 진짜 새 환경에서 정상 동작하는지 확인. 이건 이번 프로젝트에서 로컬 Docker 문제로 한 번도 제대로 검증 못 했던 것과 같은 종류의 "실제 환경 첫 검증"이므로, CI에서처럼 예상 못 한 문제가 나올 수 있다는 점을 감안한다.

### 스코프 밖
- 환전 알림(FCM) 기능 — 별도 브레인스토밍
- 도메인 구매/HTTPS — 나중에 필요해지면 진행
- CI/CD 자동 배포 — 나중에 필요해지면 진행
