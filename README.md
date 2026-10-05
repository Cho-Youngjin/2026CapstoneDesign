# 해외여행 발걸음 (travel-footsteps)

해외여행 준비부터 여행 중 활동까지를 하나로 묶는 Android 앱.

## 구조

- `app/` — Flutter (Android 전용)
- `server/` — Spring Boot API 서버
- `osrm/` — 발걸음 실시간 경로 도로 스냅용 OSRM 서버(Docker) — 자세한 건 `osrm/README.md`
- `docs/superpowers/specs/` — 설계 문서
- `docs/superpowers/plans/` — 구현 계획

## 개발 환경

- Flutter 3.x (stable), Dart
- Java 21, Spring Boot 3.x
- PostgreSQL 16, Docker (테스트에 Testcontainers 사용)

## 시작하기

외부 서비스 키 발급은 `docs/setup-external-services.md`를 따른다.

### 서버

    cd server
    ./gradlew bootRun

### 앱

    cd app
    flutter pub get
    flutter run

## 브랜치 전략

`main` / `develop` / `feature/*`
모든 작업은 `feature/*`에서 시작해 `develop`으로 PR한다. PR은 2인 승인.
매주 금요일 `develop` 머지 필수.

---

## R3(지도·센서) 파트 개발 현황 — ③발걸음 + ⑥주변정보

이 저장소는 R3 파트만 독립적으로 검증하기 위한 개인 백업이다(`main`, `feature/footsteps-realtime`).
팀 저장소(`Cho-Youngjin/2026CapstoneDesign`)는 별도이며 이 섹션의 작업은 아직 반영되지 않았다.

### 1. 문서 요구사항(plan-c, plan-f) 체크리스트

원본: `docs/superpowers/plans/2026-09-07-plan-c-map-footsteps.md`, `2026-09-07-plan-f-nearby-info.md`

**plan-c — 발걸음 (71개 중 69개 완료)**

| Task | 내용 | 상태 |
|---|---|---|
| 1 | drift 로컬 DB(`checkins`, `daily_steps`) | ✅ |
| 2 | 국가 판정 + 포그라운드 수동 체크인("여기 저장") | ✅ |
| 3 | WorkManager 1시간 주기 백그라운드 자동 체크인 + 배터리 최적화 예외 | ✅ (등록/콜백 로직만 검증, 실제 1시간 대기 관찰은 미완 — Step 10 미체크) |
| 4 | Health Connect 걸음 수 읽기 + 국가 귀속 | ✅ |
| 5 | Google Maps Timeline 임포트(file_picker) | ✅ (UI 코드는 있으나 실제 내보내기 파일로 인터랙션 테스트는 미완 — Step 8 미체크) |
| 6 | 서버 동기화(checkin/daily_steps 배치 push) | ✅ |
| 7 | 상위 지도 — 세계지도 choropleth + 국가별 누적 걸음 카드 | ✅ |
| 8 | 하위 지도 — 국가별 점선 경로 + `FootstepsPage` 통합 | ✅ |

**plan-f — 주변정보 (53개 전부 완료)**

| Task | 내용 | 상태 |
|---|---|---|
| 1 | 현재 위치 획득 + 카테고리/국가 선택 상태 | ✅ |
| 2 | Places API 연동 + 필터 탭 + 리스트 | ✅ |
| 3 | 지도 마커 표시 | ✅ |
| 4 | 여행경보 + 재외공관 API 연동(전화 연결 포함) | ✅ |
| 5 | `NearbyPage` 통합 | ✅ |

### 2. 문서에 없지만 추가로 구현한 것

플랫폼 이슈 대응, 테스트 인프라, 사용자 요청 기반 확장 세 갈래로 나뉜다.

**실시간 이동 경로 표시(사용자 요청, 문서 범위 밖)**
- `RoutePoints` 테이블 신설 — 10m 간격으로 GPS 좌표를 국가와 함께 영구 저장(`live_route_tracker.dart`)
- 국가 상세 지도에 실시간 실선 경로 + 구분점(탭하면 기록 시각 표시) + 도로 스냅(OSRM, `route_snapping_api.dart`)
- 지도 카메라가 항상 현재 위치를 중심(10km 뷰)으로 따라가도록 변경, 이 과정에서 줌 계산 버그(11.5 → 13.7) 발견·수정
- GPS 이동거리 기반 걸음 수 독립 추정(`distance_step_estimator.dart`) — Health Connect 연동 검증용 보조 지표
- (시도했다가 되돌림) 국경을 실시간으로 자동 체크인하는 기능은 요청 범위를 벗어난 것으로 확인되어 제거 — 국가 판정은 문서 원안대로 WorkManager 1시간 + 수동 저장만 사용

**버그 수정 / 실제 배선**
- `Health Connect` 연동 코드가 작성만 되고 아무 데서도 호출되지 않던 것을 발견해 `runFootstepsSync`에 실제로 연결
- 주변정보 국가 기본값이 서버 국가 목록의 첫 항목(사실상 임의값)으로 고정돼 있던 것을 현재 GPS 위치 기준 자동 판정으로 수정(`currentLocationCountryProvider`)
- Places 검색 반경을 문서 고정값(1.5km)에서 10km로 확대
- `flutter analyze`가 `info` 레벨 힌트에도 exit 1을 반환해 CI가 계속 실패하던 원인 발견·수정

**테스트/인프라**
- `mock-server/`(코드는 개인 저장소에 보관, `.env`만 gitignore) — R1 서버 없이 R3 파트만 검증하는 표준 라이브러리 전용 Python 서버. Google Places API 실데이터 연동, 도로 스냅 백엔드(OSRM 우선/Google 폴백) 포함
- `osrm/` — 한국 도로 데이터로 도로 스냅을 검증하기 위한 Docker 구조(`docker-compose.yml`, `setup.sh`). Google Roads API가 한국 좌표에 빈 응답만 준 것을 확인하고 OSRM(OpenStreetMap 기반)으로 교체한 결과물

### 3. 더 추가할 기능 / 구현사항 (백로그)

지도교수 면담 피드백(2026-09) 반영 — 현실성보다 기술 완성도·API 다양성 우선, 물리적으로 해외에 못 가도 "해외에 있는 것과 비슷한 경험"을 국내에서 재현하는 방향.

- **해외 경로 매핑("해외 발걸음")**: 국내 실이동(거리+방향)을 사용자가 고른 해외 도시의 실제 도로망에 투영. 짧은 구간(50~100m)마다 anchor를 재설정해 Map Matching API(Mapbox 우선, 필요 시 Google Roads 보조 — Google Roads는 한국은 안 되지만 해외는 됨을 이미 확인함)로 도로 위에 재정렬. 지도 렌더링은 신규 SDK(`mapbox_maps_flutter`) 없이 기존 `google_maps_flutter` 위젯 재사용. 상세 검토는 `docs/`에 첨부된 기획서 참고
- **날씨 API 연동**: 체크인 시점 위치의 실제 날씨를 함께 기록(국내는 기상청 단기예보 API, "해외 발걸음" 가상 위치는 OpenWeatherMap) — 위치 기반, 가벼움, 타 파트와 비중복
- **대기오염정보 API(에어코리아)**: 체크인 시점 위치의 미세먼지 정보 — 역시 위치 기반, 단일 REST 호출
- **여행경보/재외공관 실데이터**: 공공데이터포털 서비스키 발급 후 mock 데이터 대체
- **물리 기기 검증 대기 항목**: WorkManager 1시간 주기 실제 백그라운드 동작, Timeline 임포트 실제 내보내기 파일 테스트, 배터리 최적화 예외 다이얼로그 — 전부 에뮬레이터로만 확인됨
- **OSRM 프로덕션 이관**: 현재 로컬 Docker 실험 단계. 팀 배포 파이프라인(R1 담당, Oracle Cloud + Docker Compose)에 편입하려면 R1과 조율 필요

### 4. 핵심 코드 설명

#### 앱(Flutter) — `app/lib/features/footsteps/`

| 파일 | 역할 |
|---|---|
| `data/footsteps_repository.dart` | 발걸음 도메인의 단일 진입점. 체크인 기록·조회, RoutePoint 기록·조회, 걸음 수 upsert 등 DB 접근을 전부 이 클래스로 모은다 |
| `data/country_resolver.dart` / `geocoding_country_resolver.dart` / `polygon_country_resolver.dart` | 좌표→국가 판정의 공통 인터페이스와 두 구현체. `GeocodingCountryResolver`는 외부 API 기반(정확하지만 느림, 체크인용), `PolygonCountryResolver`는 로컬 GeoJSON point-in-polygon 기반(즉시·오프라인, 실시간 경로 판정용) |
| `background/footstep_workmanager.dart` + `footstep_task_handler.dart` | WorkManager 1시간 주기 자동 체크인. 콜백 진입점(별도 isolate)과 순수 판단 로직(`handleFootstepTask`, 단위 테스트 가능)을 분리한 게 핵심 |
| `map/live_route_tracker.dart` | 실시간 이동 경로의 핵심. GPS 스트림을 받아 `RoutePoints`에 영구 저장하면서 동시에 화면 표시용 좌표 리스트를 스트림으로 낸다 |
| `data/route_snapping_api.dart` | 도로 스냅 서버 호출(`POST /api/route/snap`). 실패해도 원본 좌표를 그대로 돌려주므로 호출부에 별도 예외 처리가 필요 없다 |
| `map/country_detail_map_page.dart` | 국가 상세 지도. 체크인(점선)과 RoutePoint(실선+구분점+도로 스냅)를 같은 날짜 기준으로 겹쳐 그리고, 카메라가 실시간 위치를 따라가게 한다 |
| `providers/footsteps_providers.dart` | Riverpod provider 모음. `liveRouteProvider`가 실시간 추적의 스위치(`realtimeTrackingEnabledProvider`)와 GPS 스트림·저장·화면표시를 전부 묶는다 |
| `health/distance_step_estimator.dart` | GPS 이동거리(Haversine)로 걸음 수를 독립 추정하는 순수 함수. Health Connect 없이도 동작 |

#### 앱(Flutter) — `app/lib/features/nearby/`

| 파일 | 역할 |
|---|---|
| `providers/nearby_selection_providers.dart` | 카테고리/국가 선택 상태 + `currentLocationCountryProvider`(GPS 기준 국가 자동 판정, footsteps의 `PolygonCountryResolver` 재사용) |
| `api/places_api.dart` | Places 조회. `nearbySearchRadiusMeters`(10km)로 서버에 반경을 실어 보낸다 |
| `api/embassy_api.dart`, `travel_alert_api.dart` | 국가별 재외공관·여행경보 조회 — 둘 다 `/api/countries/{iso2}/...` 패턴 |
| `widgets/embassy_card.dart` | `url_launcher`로 `tel:` 스킴을 직접 호출해 대표전화/긴급연락 버튼을 실제 전화 연결로 구현 |

#### 서버(로컬 검증용) — `mock-server/mock_server.py`

R1의 실제 Spring 서버 없이 R3 파트만 검증하기 위한 표준 라이브러리 전용 Python HTTP 서버. `.env`로 실제 API 키를 넣으면 진짜 데이터를 반환하고, 없으면 목 데이터로 조용히 폴백한다.

- `fetch_real_places` — Google Places Nearby Search 프록시(`GOOGLE_SERVER_API_KEY`)
- `snap_to_roads` / `_snap_via_osrm` / `_snap_via_google` — 도로 스냅. `OSRM_BASE_URL`이 있으면 OSRM(한국 도로 데이터 보유)을 우선 쓰고, 없거나 실패하면 Google Roads API(한국은 항상 빈 응답, 해외는 동작)로 폴백
- 나머지(`/api/countries`, `/api/checkins`, `/api/daily-steps` 등)는 고정 목 데이터
- 해외 매핑(`/api/route/overseas-anchor/validate`, `/api/route/overseas-walk`)은 Spring 서버(`server/.../route/`)에도 같은 계약으로 구현돼 있다(2026-10-04 이관). 알고리즘을 고칠 때는 둘을 함께 맞춘다

#### 인프라 — `osrm/`

`docker-compose.yml` + `setup.sh`로 한국 OSM 데이터를 받아 도보 프로필로 전처리하고 OSRM 서버를 띄운다. Google Roads API가 한국 좌표에 전부 빈 응답을 준 걸 실측 확인(서울/부산/강남/제주 전부 테스트, 뉴욕은 정상)한 뒤 대체한 결과물 — 자세한 배경은 `osrm/README.md` 참고.
