# Phase 0 — 기반 구축 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 4명이 병렬로 갈라지기 위한 공통 기반을 만든다. 앱에서 Google 로그인 후 6개 탭을 이동할 수 있고, 서버가 그 토큰을 검증해 DB에서 국가 목록을 돌려준다. (M1 게이트)

**Architecture:** Flutter(Android) 앱이 Firebase Auth로 로그인해 ID Token을 얻고, 이 토큰을 `Authorization: Bearer` 헤더로 Spring Boot 서버에 보낸다. 서버는 Firebase Admin SDK로 토큰을 검증하고 `uid`를 꺼내 쓴다. 자체 회원 테이블·JWT 발급은 만들지 않는다. 데이터는 PostgreSQL에 두고 Flyway로 스키마를 관리한다.

**Tech Stack:** Flutter 3.x / Riverpod / go_router / dio · Spring Boot 3.x / Java 21 / Spring Data JPA / Spring Security / Flyway · PostgreSQL 16 · Firebase Auth + Admin SDK · GitHub Actions · Testcontainers

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md`

## Global Constraints

- **모노레포 구조**: `app/` (Flutter), `server/` (Spring Boot), `docs/` — 저장소 하나로 관리한다.
- **Android 전용.** iOS 빌드 설정은 손대지 않는다.
- **비밀정보를 커밋하지 않는다.** `google-services.json`, `firebase-service-account.json`, `.env`, `local.properties`는 `.gitignore`에 등록되어 있다. 키는 각자 로컬에 두고 팀 공유는 Discord DM 등 저장소 밖에서 한다.
- **브랜치 전략**: `main` / `develop` / `feature/*`. 모든 작업은 `feature/*`에서 시작해 `develop`으로 PR한다. PR은 2인 승인.
- **매주 금요일 `develop` 머지 필수.** 통합을 뒤로 미루지 않는다.
- **인증 추상화 규칙 (스펙 §3)**: 화면은 `signInWithGoogle()`을 직접 호출하지 않고 `AuthRepository`를 경유한다. `uid` 외의 사용자 속성(`displayName`, `photoUrl`, `email`)은 전부 nullable로 다룬다.
- **패키지 루트**: `com.travelfootsteps`
- **서버 포트**: 8080. 안드로이드 에뮬레이터에서 호스트는 `10.0.2.2`.

## 담당 배분

| 태스크 | 담당 | 비고 |
|---|---|---|
| Task 1 | 전원 | 저장소·CI. 가장 먼저 |
| Task 2 | 전원 | 외부 계정·키. **Task 1과 동시 착수** (승인 대기 시간이 있음) |
| Task 3~6 | R1 | 서버 |
| Task 7~9 | R2 | 앱 |
| 병행 | R3, R4 | Figma 와이어프레임, Tier A 20개국 데이터 조사 — 이 계획서 범위 밖 |

Task 3~6과 Task 7~9는 서로 의존하지 않으므로 **병렬로 진행한다.** Task 9만 양쪽이 끝나야 한다.

---

## File Structure

```
travel-footsteps/
├── .github/workflows/ci.yml            CI: flutter analyze/test + gradle test
├── .gitignore
├── README.md                           설정 방법, 실행 방법
├── docs/
│   ├── superpowers/specs/              설계 문서
│   ├── superpowers/plans/              구현 계획
│   └── setup-external-services.md      외부 서비스 발급 절차 (Task 2)
├── app/                                Flutter
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart                   진입점, Firebase 초기화
│   │   ├── app.dart                    MaterialApp.router
│   │   ├── router.dart                 go_router 라우트 정의 (6탭 + 로그인)
│   │   ├── core/
│   │   │   ├── auth/
│   │   │   │   ├── app_user.dart       uid + nullable 프로필
│   │   │   │   ├── auth_repository.dart          추상 인터페이스
│   │   │   │   ├── firebase_auth_repository.dart Firebase 구현체
│   │   │   │   └── auth_providers.dart Riverpod provider
│   │   │   └── network/
│   │   │       ├── api_client.dart     dio + 토큰 인터셉터
│   │   │       └── country_api.dart    GET /api/countries
│   │   └── features/
│   │       ├── login/login_page.dart
│   │       ├── visa/visa_page.dart
│   │       ├── checklist/checklist_page.dart
│   │       ├── footsteps/footsteps_page.dart
│   │       ├── group/group_page.dart
│   │       ├── translate/translate_page.dart
│   │       └── nearby/nearby_page.dart
│   └── test/
│       ├── router_test.dart
│       ├── auth/fake_auth_repository.dart
│       ├── auth/auth_state_test.dart
│       └── network/api_client_test.dart
└── server/                             Spring Boot
    ├── build.gradle
    ├── src/main/java/com/travelfootsteps/
    │   ├── TravelFootstepsApplication.java
    │   ├── auth/
    │   │   ├── TokenVerifier.java          인터페이스 (테스트 대체 지점)
    │   │   ├── FirebaseTokenVerifier.java  Admin SDK 구현체
    │   │   ├── FirebaseAuthFilter.java     Bearer 토큰 → SecurityContext
    │   │   ├── FirebaseConfig.java         FirebaseApp 초기화
    │   │   └── SecurityConfig.java         필터 체인
    │   ├── country/
    │   │   ├── Country.java                JPA 엔티티
    │   │   ├── CountryRepository.java
    │   │   ├── CountryController.java      GET /api/countries
    │   │   └── CountryResponse.java        DTO
    │   └── common/HealthController.java    GET /api/health (인증 없음)
    ├── src/main/resources/
    │   ├── application.yml
    │   └── db/migration/V1__init.sql       country 테이블
    └── src/test/java/com/travelfootsteps/
        ├── auth/FirebaseAuthFilterTest.java
        ├── country/CountryControllerTest.java
        └── support/StubTokenVerifier.java
```

**분리 원칙**: `auth` 패키지는 "누가 요청했는가"만 책임진다. `country`는 도메인 데이터만 다루며 인증을 알지 못한다. `TokenVerifier` 인터페이스를 둔 이유는 테스트에서 실제 Firebase를 호출하지 않기 위해서다 — 이 경계가 없으면 모든 컨트롤러 테스트가 네트워크에 의존하게 된다.

---

### Task 1: 저장소 구조와 CI 파이프라인

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `develop` 브랜치와 CI 워크플로. 이후 모든 태스크는 `feature/*`에서 작업해 `develop`으로 PR한다.

- [ ] **Step 1: `develop` 브랜치 생성**

```bash
git checkout -b develop
```

- [ ] **Step 2: `.gitignore` 작성**

`.gitignore` 파일 전체를 아래 내용으로 교체한다.

```gitignore
# Flutter / Dart
app/build/
app/.dart_tool/
app/.flutter-plugins
app/.flutter-plugins-dependencies
app/android/local.properties
app/android/.gradle/
app/android/app/google-services.json

# Gradle / Java
server/build/
server/.gradle/
server/bin/

# 비밀정보 — 절대 커밋하지 않는다
**/firebase-service-account.json
**/*.keystore
.env
.env.*

# IDE
.idea/
*.iml
.vscode/
```

- [ ] **Step 3: `README.md` 작성**

```markdown
# 해외여행 발걸음 (travel-footsteps)

해외여행 준비부터 여행 중 활동까지를 하나로 묶는 Android 앱.

## 구조

- `app/` — Flutter (Android 전용)
- `server/` — Spring Boot API 서버
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
```

- [ ] **Step 4: CI 워크플로 작성**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, develop]

jobs:
  app:
    name: Flutter
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

  server:
    name: Spring Boot
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: server
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: gradle
      - run: chmod +x ./gradlew
      - run: ./gradlew test
```

- [ ] **Step 5: 커밋 후 푸시, CI가 도는지 확인**

```bash
git add .gitignore README.md .github/workflows/ci.yml
git commit -m "chore: 저장소 구조와 CI 파이프라인 추가"
git push -u origin develop
```

GitHub Actions 탭에서 워크플로가 실행되는지 확인한다. `app/`, `server/` 디렉터리가 아직 없으므로 **두 job 모두 실패하는 것이 정상이다.** Task 3과 Task 7에서 각각 통과하게 된다.

- [ ] **Step 6: GitHub 저장소 보호 규칙 설정**

GitHub 저장소 → Settings → Branches → Add rule:
- Branch name pattern: `develop`
- Require a pull request before merging ✓ (Required approvals: 2)
- Require status checks to pass before merging ✓ → `Flutter`, `Spring Boot` 선택

---

### Task 2: 외부 서비스 계정·키 발급

**Files:**
- Create: `docs/setup-external-services.md`

**Interfaces:**
- Consumes: 없음
- Produces: 각자 로컬에 놓인 `app/android/app/google-services.json`, `server/src/main/resources/firebase-service-account.json`, 그리고 `.env`의 `DATA_GO_KR_SERVICE_KEY`. Task 5, Task 8이 이 파일들에 의존한다.

> **Task 1과 동시에 착수한다.** 공공데이터포털 활용신청과 GCP 결제계정 승인에 대기 시간이 있어, 미루면 Task 3~9가 끝난 뒤 막힌다.

- [ ] **Step 1: 공공데이터포털 활용신청**

https://www.data.go.kr 회원가입 후 아래 4개를 **개발계정**으로 신청한다. 개발계정은 자동승인이며 일 10,000회 호출이 가능하다.

| 데이터셋 | URL |
|---|---|
| 외교부_국가·지역별 입국허가요건 | https://www.data.go.kr/data/15075345/openapi.do |
| 외교부_국가·지역별 여행경보 | https://www.data.go.kr/data/15076237/openapi.do |
| 외교부_국가·지역별 재외공관 정보 | https://www.data.go.kr/data/15075354/openapi.do |
| 외교부_국가별 여행경보 히스토리 | https://www.data.go.kr/data/15059195/openapi.do |

마이페이지 → 오픈API → 인증키에서 **일반 인증키(Decoding)** 를 복사해 둔다.

- [ ] **Step 2: 발급받은 키로 실제 호출이 되는지 확인**

`<SERVICE_KEY>` 자리에 발급받은 키를 넣고 실행한다.

```bash
curl "https://apis.data.go.kr/1262000/EntranceVisaService2/getEntranceVisaList2?serviceKey=<SERVICE_KEY>&numOfRows=1&pageNo=1&returnType=JSON&cond%5Bcountry_iso_alp2%3A%3AEQ%5D=VN"
```

기대 결과: `resultCode` 가 `00`이고 `country_nm`이 `베트남`인 JSON 응답. 신청 직후에는 키가 반영되기까지 시간이 걸릴 수 있으므로, `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`가 나오면 1시간 뒤 다시 시도한다.

> 실제 엔드포인트 URL과 파라미터명은 데이터셋 페이지의 **활용가이드 문서(참고문서)** 를 기준으로 한다. 위 URL이 다르면 가이드 문서의 값으로 바꾸고, 확인한 값을 Step 5의 문서에 기록한다.

- [ ] **Step 3: Firebase 프로젝트 생성**

1. https://console.firebase.google.com → 프로젝트 추가 → 이름 `travel-footsteps`
2. Authentication → Sign-in method → **Google 사용 설정**
3. Firestore Database 생성 (프로덕션 모드, 리전 `asia-northeast3`)
4. Storage 생성 (같은 리전)
5. 프로젝트 설정 → Android 앱 추가 → 패키지명 `com.travelfootsteps.app`
   - 디버그 서명 인증서 SHA-1 등록 (Google 로그인에 필수):
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
     출력의 SHA1 값을 등록한다. **팀원 4명이 각자 자기 SHA-1을 등록해야 한다.**
   - `google-services.json` 다운로드 → `app/android/app/google-services.json`에 저장
6. 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성 → `server/src/main/resources/firebase-service-account.json`에 저장

- [ ] **Step 4: GCP 결제계정과 API 키**

Firebase 프로젝트는 GCP 프로젝트와 동일하다. https://console.cloud.google.com 에서:

1. 결제 → 결제 계정 연결 (카드 등록 필요)
2. **결제 → 예산 및 알림 → 예산 만들기 → $10, 임계값 50%/90%/100% 알림** ← 반드시 먼저 한다
3. API 및 서비스 → 라이브러리에서 사용 설정:
   - Maps SDK for Android
   - Places API
   - Cloud Translation API
4. 사용자 인증 정보 → API 키 2개 생성
   - **Maps용**: 애플리케이션 제한 = Android 앱 (패키지명 + SHA-1), API 제한 = Maps SDK for Android
   - **서버용**: 애플리케이션 제한 = IP 주소, API 제한 = Places API + Cloud Translation API

- [ ] **Step 5: 발급 절차와 값의 위치를 문서화**

`docs/setup-external-services.md`를 작성한다. **키 값 자체는 절대 적지 않는다.** 어디서 받고 어디에 두는지만 적는다.

```markdown
# 외부 서비스 설정

키 값은 이 문서에 적지 않는다. 팀 공유는 저장소 밖(Discord DM 등)에서 한다.

## 필요한 파일 (각자 로컬에 배치, 커밋 금지)

| 파일 | 위치 | 출처 |
|---|---|---|
| `google-services.json` | `app/android/app/` | Firebase 콘솔 → 프로젝트 설정 → Android 앱 |
| `firebase-service-account.json` | `server/src/main/resources/` | Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 |
| `.env` | 저장소 루트 | 아래 항목 참고 |

## `.env` 항목

    DATA_GO_KR_SERVICE_KEY=<공공데이터포털 일반 인증키(Decoding)>
    GOOGLE_SERVER_API_KEY=<GCP 서버용 API 키>
    MAPS_ANDROID_API_KEY=<GCP Maps용 API 키>
    DB_URL=jdbc:postgresql://localhost:5432/travelfootsteps
    DB_USERNAME=postgres
    DB_PASSWORD=postgres

## 공공데이터포털

개발계정(자동승인, 일 10,000회)으로 신청한다. 신청 데이터셋 4종과 확인된
엔드포인트는 설계 문서 §4 참고.

## Firebase

- Authentication: Google 로그인 사용 설정
- Firestore, Storage: 리전 `asia-northeast3`
- **팀원 각자가 자기 디버그 SHA-1을 등록해야 Google 로그인이 동작한다.**

      keytool -list -v -keystore ~/.android/debug.keystore \
        -alias androiddebugkey -storepass android -keypass android

## GCP

- **예산 알림 $10을 먼저 설정한다.**
- 사용 설정할 API: Maps SDK for Android, Places API, Cloud Translation API
- API 키 2개를 분리하고 각각 제한을 건다 (Android 앱 제한 / IP 제한)
```

- [ ] **Step 6: 커밋**

```bash
git add docs/setup-external-services.md
git commit -m "docs: 외부 서비스 발급 절차 문서화"
```

`git status`로 `google-services.json`과 `firebase-service-account.json`이 **추적되지 않는지 반드시 확인한다.**

---

### Task 3: Spring Boot 스켈레톤과 헬스 체크

**Files:**
- Create: `server/` (Spring Initializr 생성물 전체)
- Create: `server/src/main/java/com/travelfootsteps/common/HealthController.java`
- Test: `server/src/test/java/com/travelfootsteps/common/HealthControllerTest.java`

**Interfaces:**
- Consumes: Task 1의 CI 워크플로 (`server` job이 이 태스크로 통과하게 된다)
- Produces: `GET /api/health` → `200 {"status":"UP"}`. 인증 없이 접근 가능하며, Task 5의 SecurityConfig에서도 permitAll로 유지된다.

- [ ] **Step 1: Spring Initializr로 프로젝트 생성**

https://start.spring.io 에서 아래 설정으로 생성해 `server/`에 압축을 푼다.

- Project: **Gradle - Groovy**
- Language: **Java**
- Spring Boot: **최신 3.x 안정 버전**
- Group: `com.travelfootsteps` / Artifact: `server` / Package name: `com.travelfootsteps`
- Packaging: Jar / Java: **21**
- Dependencies: **Spring Web**, **Spring Data JPA**, **Spring Security**, **Validation**, **Flyway Migration**, **PostgreSQL Driver**, **Lombok**, **Testcontainers**

- [ ] **Step 2: 추가 의존성 등록**

`server/build.gradle`의 `dependencies` 블록에 아래를 추가한다.

```gradle
    implementation 'com.google.firebase:firebase-admin:9.4.1'
    testImplementation 'org.springframework.boot:spring-boot-testcontainers'
    testImplementation 'org.testcontainers:junit-jupiter'
    testImplementation 'org.testcontainers:postgresql'
    testImplementation 'org.springframework.security:spring-security-test'
```

- [ ] **Step 3: `application.yml` 작성**

`server/src/main/resources/application.yml`:

```yaml
spring:
  application:
    name: travel-footsteps-server
  datasource:
    url: ${DB_URL:jdbc:postgresql://localhost:5432/travelfootsteps}
    username: ${DB_USERNAME:postgres}
    password: ${DB_PASSWORD:postgres}
  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false
  flyway:
    enabled: true

firebase:
  service-account-path: classpath:firebase-service-account.json

server:
  port: 8080

logging:
  level:
    com.travelfootsteps: DEBUG
```

`ddl-auto: validate`로 두는 이유는 스키마를 Flyway가 단독으로 관리하게 하기 위해서다. Hibernate가 테이블을 만들면 마이그레이션과 실제 스키마가 어긋난다.

- [ ] **Step 4: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/common/HealthControllerTest.java`:

```java
package com.travelfootsteps.common;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(HealthController.class)
@AutoConfigureMockMvc(addFilters = false)
class HealthControllerTest {

    @Autowired
    MockMvc mockMvc;

    @Test
    void health_returns_up() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
```

`addFilters = false`는 Task 5에서 보안 필터가 붙기 전까지 이 테스트가 인증에 영향받지 않게 한다.

- [ ] **Step 5: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*HealthControllerTest*'
```

기대: 컴파일 실패 — `HealthController` 심볼을 찾을 수 없음.

- [ ] **Step 6: 최소 구현**

`server/src/main/java/com/travelfootsteps/common/HealthController.java`:

```java
package com.travelfootsteps.common;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class HealthController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
```

- [ ] **Step 7: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*HealthControllerTest*'
```

기대: PASS.

- [ ] **Step 8: 커밋**

```bash
git add server/ 
git commit -m "feat(server): Spring Boot 스켈레톤과 헬스 체크 엔드포인트"
```

`git status`에 `firebase-service-account.json`이 없는지 확인한다.

---

### Task 4: country 테이블 마이그레이션과 엔티티

**Files:**
- Create: `server/src/main/resources/db/migration/V1__init.sql`
- Create: `server/src/main/java/com/travelfootsteps/country/Country.java`
- Create: `server/src/main/java/com/travelfootsteps/country/CountryRepository.java`
- Test: `server/src/test/java/com/travelfootsteps/country/CountryRepositoryTest.java`

**Interfaces:**
- Consumes: Task 3의 `application.yml` (Flyway 설정, 데이터소스)
- Produces:
  - 테이블 `country`
  - `Country` 엔티티 — getter: `getId()`, `getIsoAlpha2()`, `getNameKo()`, `getNameEn()`, `getTier()`
  - `CountryRepository extends JpaRepository<Country, Long>` — `Optional<Country> findByIsoAlpha2(String isoAlpha2)`, `List<Country> findAllByOrderByNameKoAsc()`
  - Plan A(서버 데이터 파이프라인)가 이 테이블에 컬럼을 추가하는 `V2__*.sql`부터 이어간다.

> **스키마 범위에 대해**: 스펙 §7에 전체 데이터 모델(`visa_requirement`, `trip`, `checkin` 등)이 정의돼 있지만, Phase 0에서는 `country` 하나만 만든다. 나머지 테이블은 그것을 쓰는 계획서가 각자 마이그레이션(`V2`, `V3`, …)으로 추가한다. 지금 전부 만들면 실제로 쓰기 전에 컬럼이 바뀌어 마이그레이션을 다시 쓰게 된다. 병렬 작업의 전제인 **API 응답 계약**은 스펙 §7의 엔드포인트 목록이 이미 담당하고 있으므로, 이 결정이 다른 팀원을 막지 않는다.

- [ ] **Step 1: 마이그레이션 작성**

`server/src/main/resources/db/migration/V1__init.sql`:

```sql
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
```

- [ ] **Step 2: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/country/CountryRepositoryTest.java`:

```java
package com.travelfootsteps.country;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class CountryRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void flyway(DynamicPropertyRegistry registry) {
        registry.add("spring.flyway.enabled", () -> "true");
    }

    @Autowired
    CountryRepository countryRepository;

    @Test
    void seed_contains_20_tier_a_countries() {
        assertThat(countryRepository.findAll()).hasSize(20);
    }

    @Test
    void findByIsoAlpha2_returns_country() {
        Optional<Country> vietnam = countryRepository.findByIsoAlpha2("VN");

        assertThat(vietnam).isPresent();
        assertThat(vietnam.get().getNameKo()).isEqualTo("베트남");
        assertThat(vietnam.get().getTier()).isEqualTo("A");
    }

    @Test
    void findAllByOrderByNameKoAsc_is_sorted() {
        var names = countryRepository.findAllByOrderByNameKoAsc()
                .stream().map(Country::getNameKo).toList();

        assertThat(names).isSorted();
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*CountryRepositoryTest*'
```

기대: 컴파일 실패 — `Country`, `CountryRepository` 심볼을 찾을 수 없음.

> Docker Desktop이 실행 중이어야 한다. `Could not find a valid Docker environment` 오류가 나면 Docker를 먼저 켠다.

- [ ] **Step 4: 엔티티 구현**

`server/src/main/java/com/travelfootsteps/country/Country.java`:

```java
package com.travelfootsteps.country;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

@Entity
@Table(name = "country")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Country {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "iso_alpha2", nullable = false, unique = true, length = 2)
    private String isoAlpha2;

    @Column(name = "iso_alpha3", length = 3)
    private String isoAlpha3;

    @Column(name = "name_ko", nullable = false, length = 100)
    private String nameKo;

    @Column(name = "name_en", length = 100)
    private String nameEn;

    @Column(length = 50)
    private String continent;

    @Column(nullable = false, length = 1)
    private String tier;

    @Column(name = "plug_types", length = 50)
    private String plugTypes;

    @Column(name = "voltage_v")
    private Integer voltageV;

    @Column(name = "frequency_hz")
    private Integer frequencyHz;

    @Column(name = "currency_code", length = 3)
    private String currencyCode;

    @Column(name = "card_acceptance", length = 10)
    private String cardAcceptance;

    @Column(name = "power_bank_wh_limit")
    private Integer powerBankWhLimit;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;
}
```

- [ ] **Step 5: 리포지토리 구현**

`server/src/main/java/com/travelfootsteps/country/CountryRepository.java`:

```java
package com.travelfootsteps.country;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CountryRepository extends JpaRepository<Country, Long> {

    Optional<Country> findByIsoAlpha2(String isoAlpha2);

    List<Country> findAllByOrderByNameKoAsc();
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*CountryRepositoryTest*'
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 7: 커밋**

```bash
git add server/src/main/resources/db/migration server/src/main/java/com/travelfootsteps/country server/src/test/java/com/travelfootsteps/country
git commit -m "feat(server): country 테이블 마이그레이션과 엔티티"
```

---

### Task 5: Firebase ID Token 검증

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/auth/TokenVerifier.java`
- Create: `server/src/main/java/com/travelfootsteps/auth/FirebaseTokenVerifier.java`
- Create: `server/src/main/java/com/travelfootsteps/auth/FirebaseConfig.java`
- Create: `server/src/main/java/com/travelfootsteps/auth/FirebaseAuthFilter.java`
- Create: `server/src/main/java/com/travelfootsteps/auth/SecurityConfig.java`
- Test: `server/src/test/java/com/travelfootsteps/support/StubTokenVerifier.java`
- Test: `server/src/test/java/com/travelfootsteps/auth/FirebaseAuthFilterTest.java`

**Interfaces:**
- Consumes: Task 3의 `application.yml` (`firebase.service-account-path`)
- Produces:
  - `TokenVerifier` 인터페이스 — `String verifyAndGetUid(String idToken) throws InvalidTokenException`
  - `InvalidTokenException` — `RuntimeException` 상속
  - 인증된 요청에서 `SecurityContextHolder.getContext().getAuthentication().getName()` 이 Firebase `uid`를 반환한다. Task 6과 이후 모든 컨트롤러가 이 방식으로 사용자를 식별한다.
  - `/api/health`는 인증 없이 접근 가능. 그 외 `/api/**`는 인증 필요.

- [ ] **Step 1: 인터페이스와 예외 정의**

`server/src/main/java/com/travelfootsteps/auth/TokenVerifier.java`:

```java
package com.travelfootsteps.auth;

public interface TokenVerifier {

    /**
     * Firebase ID Token을 검증하고 uid를 반환한다.
     *
     * @throws InvalidTokenException 토큰이 유효하지 않은 경우
     */
    String verifyAndGetUid(String idToken);

    class InvalidTokenException extends RuntimeException {
        public InvalidTokenException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
```

이 인터페이스가 있어야 테스트에서 실제 Firebase를 호출하지 않는다. 컨트롤러 테스트 전부가 이 경계에 의존한다.

- [ ] **Step 2: 테스트용 스텁 작성**

`server/src/test/java/com/travelfootsteps/support/StubTokenVerifier.java`:

```java
package com.travelfootsteps.support;

import com.travelfootsteps.auth.TokenVerifier;

import java.util.HashMap;
import java.util.Map;

/** 테스트에서 실제 Firebase 호출을 대체한다. 등록한 토큰만 유효하게 취급한다. */
public class StubTokenVerifier implements TokenVerifier {

    private final Map<String, String> tokenToUid = new HashMap<>();

    public void register(String idToken, String uid) {
        tokenToUid.put(idToken, uid);
    }

    @Override
    public String verifyAndGetUid(String idToken) {
        String uid = tokenToUid.get(idToken);
        if (uid == null) {
            throw new InvalidTokenException("unknown token: " + idToken, null);
        }
        return uid;
    }
}
```

- [ ] **Step 3: 실패하는 필터 테스트 작성**

`server/src/test/java/com/travelfootsteps/auth/FirebaseAuthFilterTest.java`:

```java
package com.travelfootsteps.auth;

import com.travelfootsteps.support.StubTokenVerifier;
import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.context.SecurityContextHolder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class FirebaseAuthFilterTest {

    StubTokenVerifier verifier;
    FirebaseAuthFilter filter;
    FilterChain chain;

    @BeforeEach
    void setUp() {
        verifier = new StubTokenVerifier();
        verifier.register("valid-token", "uid-123");
        filter = new FirebaseAuthFilter(verifier);
        chain = mock(FilterChain.class);
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void valid_bearer_token_sets_uid_as_principal() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/countries");
        request.addHeader("Authorization", "Bearer valid-token");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNotNull();
        assertThat(SecurityContextHolder.getContext().getAuthentication().getName())
                .isEqualTo("uid-123");
        verify(chain).doFilter(request, response);
    }

    @Test
    void invalid_token_leaves_context_empty() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/countries");
        request.addHeader("Authorization", "Bearer garbage");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        verify(chain).doFilter(request, response);
    }

    @Test
    void missing_header_leaves_context_empty() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/countries");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication()).isNull();
        verify(chain).doFilter(request, response);
    }
}
```

필터가 직접 401을 쓰지 않고 컨텍스트를 비워 두는 이유는, 거절 응답을 Spring Security의 `AuthenticationEntryPoint`가 일관되게 처리하도록 맡기기 위해서다.

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*FirebaseAuthFilterTest*'
```

기대: 컴파일 실패 — `FirebaseAuthFilter` 심볼을 찾을 수 없음.

- [ ] **Step 5: 필터 구현**

`server/src/main/java/com/travelfootsteps/auth/FirebaseAuthFilter.java`:

```java
package com.travelfootsteps.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

@Slf4j
@RequiredArgsConstructor
public class FirebaseAuthFilter extends OncePerRequestFilter {

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    private final TokenVerifier tokenVerifier;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String header = request.getHeader(HEADER);

        if (header != null && header.startsWith(PREFIX)) {
            String idToken = header.substring(PREFIX.length());
            try {
                String uid = tokenVerifier.verifyAndGetUid(idToken);
                var authentication = new UsernamePasswordAuthenticationToken(uid, null, List.of());
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (TokenVerifier.InvalidTokenException e) {
                log.debug("토큰 검증 실패: {}", e.getMessage());
                SecurityContextHolder.clearContext();
            }
        }

        chain.doFilter(request, response);
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd server && ./gradlew test --tests '*FirebaseAuthFilterTest*'
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 7: Firebase 초기화와 실제 구현체 작성**

`server/src/main/java/com/travelfootsteps/auth/FirebaseConfig.java`:

```java
package com.travelfootsteps.auth;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.FirebaseAuth;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.Resource;

import java.io.IOException;
import java.io.InputStream;

@Configuration
@Profile("!test")
public class FirebaseConfig {

    @Value("${firebase.service-account-path}")
    private Resource serviceAccount;

    @Bean
    public FirebaseApp firebaseApp() throws IOException {
        if (!FirebaseApp.getApps().isEmpty()) {
            return FirebaseApp.getInstance();
        }
        try (InputStream in = serviceAccount.getInputStream()) {
            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(in))
                    .build();
            return FirebaseApp.initializeApp(options);
        }
    }

    @Bean
    public FirebaseAuth firebaseAuth(FirebaseApp app) {
        return FirebaseAuth.getInstance(app);
    }
}
```

`server/src/main/java/com/travelfootsteps/auth/FirebaseTokenVerifier.java`:

```java
package com.travelfootsteps.auth;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("!test")
@RequiredArgsConstructor
public class FirebaseTokenVerifier implements TokenVerifier {

    private final FirebaseAuth firebaseAuth;

    @Override
    public String verifyAndGetUid(String idToken) {
        try {
            return firebaseAuth.verifyIdToken(idToken).getUid();
        } catch (FirebaseAuthException e) {
            throw new InvalidTokenException("Firebase ID Token 검증 실패", e);
        }
    }
}
```

`@Profile("!test")`를 붙인 이유는 테스트가 서비스 계정 키 파일 없이 뜨게 하기 위해서다. 테스트에서는 `StubTokenVerifier`를 빈으로 주입한다.

- [ ] **Step 8: SecurityConfig 작성**

`server/src/main/java/com/travelfootsteps/auth/SecurityConfig.java`:

```java
package com.travelfootsteps.auth;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http, TokenVerifier tokenVerifier)
            throws Exception {
        return http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/health").permitAll()
                        .requestMatchers("/api/**").authenticated()
                        .anyRequest().denyAll())
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
                .addFilterBefore(new FirebaseAuthFilter(tokenVerifier),
                        UsernamePasswordAuthenticationFilter.class)
                .build();
    }
}
```

세션을 STATELESS로 두는 이유는 매 요청이 ID Token으로 자기 자신을 증명하기 때문이다. 세션을 만들면 토큰 만료와 세션 수명이 어긋난다.

- [ ] **Step 9: 깨진 `HealthControllerTest` 고치기**

먼저 실행해서 깨지는 것을 확인한다.

```bash
cd server && ./gradlew test --tests '*HealthControllerTest*'
```

기대: 컨텍스트 로드 실패 — `No qualifying bean of type 'com.travelfootsteps.auth.TokenVerifier'`.

`@WebMvcTest` 슬라이스는 `SecurityConfig`를 로드하지만 `FirebaseTokenVerifier`는 `@Profile("!test")`라 빈이 없다. 스텁을 주입해 해결한다. `HealthControllerTest.java` 전체를 아래로 교체한다.

```java
package com.travelfootsteps.common;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(HealthController.class)
@ActiveProfiles("test")
@Import(HealthControllerTest.TestBeans.class)
class HealthControllerTest {

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            return new StubTokenVerifier();
        }
    }

    @Autowired
    MockMvc mockMvc;

    @Test
    void health_returns_up_without_token() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
```

`addFilters = false`를 뺀 이유는, 이제 **보안 필터가 걸린 상태에서도 `/api/health`가 열려 있는지**를 검증하는 것이 이 테스트의 목적이 됐기 때문이다.

- [ ] **Step 10: 전체 테스트 실행**

```bash
cd server && ./gradlew test
```

기대: 전체 PASS.

- [ ] **Step 11: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/auth server/src/test/java/com/travelfootsteps/auth server/src/test/java/com/travelfootsteps/support
git commit -m "feat(server): Firebase ID Token 검증 필터와 보안 설정"
```

---

### Task 6: GET /api/countries 엔드포인트

**Files:**
- Create: `server/src/main/java/com/travelfootsteps/country/CountryResponse.java`
- Create: `server/src/main/java/com/travelfootsteps/country/CountryController.java`
- Test: `server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java`

**Interfaces:**
- Consumes: Task 4의 `CountryRepository`, Task 5의 `TokenVerifier` / `SecurityConfig`
- Produces: `GET /api/countries` → `200 [{"isoAlpha2":"...","nameKo":"...","nameEn":"...","continent":"...","tier":"..."}]`, 한글명 오름차순. 인증 없으면 `401`. Task 9의 Flutter `CountryApi`가 이 계약에 맞춘다.

- [ ] **Step 1: 실패하는 테스트 작성**

`server/src/test/java/com/travelfootsteps/country/CountryControllerTest.java`:

```java
package com.travelfootsteps.country;

import com.travelfootsteps.auth.TokenVerifier;
import com.travelfootsteps.support.StubTokenVerifier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Testcontainers
@Import(CountryControllerTest.TestBeans.class)
class CountryControllerTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @TestConfiguration
    static class TestBeans {
        @Bean
        TokenVerifier tokenVerifier() {
            StubTokenVerifier stub = new StubTokenVerifier();
            stub.register("valid-token", "uid-123");
            return stub;
        }
    }

    @Autowired
    MockMvc mockMvc;

    @Test
    void without_token_returns_401() throws Exception {
        mockMvc.perform(get("/api/countries"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void with_valid_token_returns_countries_sorted_by_korean_name() throws Exception {
        mockMvc.perform(get("/api/countries").header("Authorization", "Bearer valid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(20))
                .andExpect(jsonPath("$[0].nameKo").value("대만"))
                .andExpect(jsonPath("$[0].isoAlpha2").value("TW"))
                .andExpect(jsonPath("$[0].tier").value("A"));
    }

    @Test
    void health_is_accessible_without_token() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk());
    }
}
```

> 첫 원소가 `대만`인 이유는 한글 가나다순에서 20개국 중 가장 앞이기 때문이다. 정렬은 PostgreSQL의 콜레이션을 따른다. 만약 실제 결과가 다르면 **테스트를 실제 결과에 맞추지 말고**, `V1__init.sql`의 목록을 직접 정렬해 확인한 뒤 기대값을 고친다.

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd server && ./gradlew test --tests '*CountryControllerTest*'
```

기대: 컴파일 실패 — `CountryController` 심볼을 찾을 수 없음.

- [ ] **Step 3: DTO 구현**

`server/src/main/java/com/travelfootsteps/country/CountryResponse.java`:

```java
package com.travelfootsteps.country;

public record CountryResponse(
        String isoAlpha2,
        String nameKo,
        String nameEn,
        String continent,
        String tier
) {
    public static CountryResponse from(Country country) {
        return new CountryResponse(
                country.getIsoAlpha2(),
                country.getNameKo(),
                country.getNameEn(),
                country.getContinent(),
                country.getTier()
        );
    }
}
```

엔티티를 그대로 반환하지 않는 이유는 응답 계약을 DB 스키마 변경으로부터 분리하기 위해서다. Plan A에서 `country` 테이블에 컬럼이 추가돼도 이 응답은 바뀌지 않는다.

- [ ] **Step 4: 컨트롤러 구현**

`server/src/main/java/com/travelfootsteps/country/CountryController.java`:

```java
package com.travelfootsteps.country;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/countries")
@RequiredArgsConstructor
public class CountryController {

    private final CountryRepository countryRepository;

    @GetMapping
    public List<CountryResponse> list() {
        return countryRepository.findAllByOrderByNameKoAsc()
                .stream()
                .map(CountryResponse::from)
                .toList();
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
cd server && ./gradlew test
```

기대: 전체 테스트 PASS.

- [ ] **Step 6: 서버를 실제로 띄워 확인**

로컬 PostgreSQL이 없다면 먼저 띄운다.

```bash
docker run -d --name tf-postgres -p 5432:5432 \
  -e POSTGRES_DB=travelfootsteps \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  postgres:16-alpine
```

서버 실행 후 확인:

```bash
cd server && ./gradlew bootRun
```

다른 터미널에서:

```bash
curl -i http://localhost:8080/api/health
curl -i http://localhost:8080/api/countries
```

기대: 첫 번째는 `200 {"status":"UP"}`, 두 번째는 `401`.

- [ ] **Step 7: 커밋**

```bash
git add server/src/main/java/com/travelfootsteps/country server/src/test/java/com/travelfootsteps/country
git commit -m "feat(server): 국가 목록 조회 엔드포인트"
```

---

### Task 7: Flutter 스켈레톤과 6탭 라우팅

**Files:**
- Create: `app/` (flutter create 생성물)
- Create: `app/lib/app.dart`, `app/lib/router.dart`
- Create: `app/lib/features/{visa,checklist,footsteps,group,translate,nearby}/*_page.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/router_test.dart`

**Interfaces:**
- Consumes: Task 1의 CI 워크플로 (`app` job이 이 태스크로 통과하게 된다)
- Produces:
  - 라우트 경로 상수 — `AppRoutes.login`, `.visa`, `.checklist`, `.footsteps`, `.group`, `.translate`, `.nearby`, 그리고 `AppRoutes.tabs` / `.tabLabels` / `.tabIcons`
  - `GoRouter createRouter({required bool isLoggedIn, VoidCallback? onSignIn})` — Task 8이 이 시그니처를 인증 상태와 연결한다
  - 6개 페이지 위젯 — `VisaPage`, `ChecklistPage`, `FootstepsPage`, `GroupPage`, `TranslatePage`, `NearbyPage`. Plan B~F가 각 페이지의 내용을 채운다.

- [ ] **Step 1: Flutter 프로젝트 생성**

저장소 루트에서 실행한다.

```bash
flutter create --org com.travelfootsteps --platforms android --project-name app app
```

- [ ] **Step 2: 의존성 추가**

```bash
cd app
flutter pub add flutter_riverpod go_router dio
flutter pub add firebase_core firebase_auth google_sign_in
```

- [ ] **Step 3: 실패하는 라우터 테스트 작성**

`app/test/router_test.dart`:

```dart
import 'package:app/app.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpApp(WidgetTester tester, {required bool isLoggedIn}) async {
  await tester.pumpWidget(
    TravelFootstepsApp(router: createRouter(isLoggedIn: isLoggedIn)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AppRoutes', () {
    test('6개 탭 경로가 순서대로 정의되어 있다', () {
      expect(AppRoutes.tabs, [
        AppRoutes.visa,
        AppRoutes.checklist,
        AppRoutes.footsteps,
        AppRoutes.group,
        AppRoutes.translate,
        AppRoutes.nearby,
      ]);
    });

    test('탭 라벨과 아이콘 개수가 탭 개수와 같다', () {
      expect(AppRoutes.tabLabels, hasLength(AppRoutes.tabs.length));
      expect(AppRoutes.tabIcons, hasLength(AppRoutes.tabs.length));
    });
  });

  group('createRouter', () {
    testWidgets('로그인하지 않으면 로그인 화면이 보인다', (tester) async {
      await pumpApp(tester, isLoggedIn: false);

      expect(find.text('Google로 계속하기'), findsOneWidget);
    });

    testWidgets('로그인했으면 첫 탭(비자)이 보인다', (tester) async {
      await pumpApp(tester, isLoggedIn: true);

      expect(find.text('Google로 계속하기'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      // AppBar 제목과 본문에 각각 '비자'가 있다
      expect(find.text('비자'), findsWidgets);
    });

    testWidgets('탭을 누르면 해당 화면으로 이동한다', (tester) async {
      await pumpApp(tester, isLoggedIn: true);

      await tester.tap(find.text('발걸음').last);
      await tester.pumpAndSettle();

      expect(find.text('발걸음'), findsWidgets);
      expect(find.text('준비물'), findsOneWidget); // 탭 라벨만 남는다
    });
  });
}
```

위젯 테스트로 쓰는 이유는 `GoRouter`의 리다이렉트가 라우터 델리게이트가 위젯 트리에 붙은 뒤에 평가되기 때문이다. 라우터 객체만 만들어 `go()`를 호출하면 실제 동작과 다르게 검증된다.

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd app && flutter test test/router_test.dart
```

기대: 컴파일 실패 — `app/router.dart`를 찾을 수 없음.

- [ ] **Step 5: 6개 페이지 위젯 작성**

각 페이지는 자기 이름을 표시하는 껍데기다. Plan B~F가 내용을 채운다.

`app/lib/features/visa/visa_page.dart`:

```dart
import 'package:flutter/material.dart';

class VisaPage extends StatelessWidget {
  const VisaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('비자'));
  }
}
```

나머지 5개도 같은 형태로 만든다. 경로·클래스명·표시 문자열은 아래와 같다.

| 파일 | 클래스 | 표시 문자열 |
|---|---|---|
| `app/lib/features/checklist/checklist_page.dart` | `ChecklistPage` | `'준비물'` |
| `app/lib/features/footsteps/footsteps_page.dart` | `FootstepsPage` | `'발걸음'` |
| `app/lib/features/group/group_page.dart` | `GroupPage` | `'그룹'` |
| `app/lib/features/translate/translate_page.dart` | `TranslatePage` | `'번역'` |
| `app/lib/features/nearby/nearby_page.dart` | `NearbyPage` | `'주변'` |

예를 들어 `checklist_page.dart`는 다음과 같다.

```dart
import 'package:flutter/material.dart';

class ChecklistPage extends StatelessWidget {
  const ChecklistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('준비물'));
  }
}
```

- [ ] **Step 6: 로그인 페이지 껍데기 작성**

`app/lib/features/login/login_page.dart`:

```dart
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('해외여행 발걸음', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onSignIn,
              child: const Text('Google로 계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`onSignIn`을 콜백으로 받는 이유는 이 위젯이 인증 구현을 알지 못하게 하기 위해서다. Task 8에서 실제 동작을 연결한다.

- [ ] **Step 7: 라우터 구현**

`app/lib/router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/checklist/checklist_page.dart';
import 'features/footsteps/footsteps_page.dart';
import 'features/group/group_page.dart';
import 'features/login/login_page.dart';
import 'features/nearby/nearby_page.dart';
import 'features/translate/translate_page.dart';
import 'features/visa/visa_page.dart';

class AppRoutes {
  static const login = '/login';
  static const visa = '/visa';
  static const checklist = '/checklist';
  static const footsteps = '/footsteps';
  static const group = '/group';
  static const translate = '/translate';
  static const nearby = '/nearby';

  static const tabs = [visa, checklist, footsteps, group, translate, nearby];

  static const tabLabels = ['비자', '준비물', '발걸음', '그룹', '번역', '주변'];

  static const tabIcons = [
    Icons.assignment_outlined,
    Icons.checklist_outlined,
    Icons.map_outlined,
    Icons.group_outlined,
    Icons.translate_outlined,
    Icons.explore_outlined,
  ];
}

GoRouter createRouter({required bool isLoggedIn, VoidCallback? onSignIn}) {
  return GoRouter(
    initialLocation: isLoggedIn ? AppRoutes.visa : AppRoutes.login,
    redirect: (context, state) {
      final goingToLogin = state.matchedLocation == AppRoutes.login;
      if (!isLoggedIn && !goingToLogin) return AppRoutes.login;
      if (isLoggedIn && goingToLogin) return AppRoutes.visa;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginPage(onSignIn: onSignIn),
      ),
      ShellRoute(
        builder: (context, state, child) => _TabScaffold(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(path: AppRoutes.visa, builder: (_, __) => const VisaPage()),
          GoRoute(path: AppRoutes.checklist, builder: (_, __) => const ChecklistPage()),
          GoRoute(path: AppRoutes.footsteps, builder: (_, __) => const FootstepsPage()),
          GoRoute(path: AppRoutes.group, builder: (_, __) => const GroupPage()),
          GoRoute(path: AppRoutes.translate, builder: (_, __) => const TranslatePage()),
          GoRoute(path: AppRoutes.nearby, builder: (_, __) => const NearbyPage()),
        ],
      ),
    ],
  );
}

class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final index = AppRoutes.tabs.indexOf(location);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppRoutes.tabLabels[index < 0 ? 0 : index]),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(AppRoutes.tabs[i]),
        destinations: [
          for (var i = 0; i < AppRoutes.tabs.length; i++)
            NavigationDestination(
              icon: Icon(AppRoutes.tabIcons[i]),
              label: AppRoutes.tabLabels[i],
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 8: `app.dart` 작성**

라우터 테스트가 `TravelFootstepsApp`을 사용하므로 이 단계까지 마쳐야 테스트가 돌아간다.

`app/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TravelFootstepsApp extends StatelessWidget {
  const TravelFootstepsApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '해외여행 발걸음',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 9: 테스트 통과 확인**

```bash
cd app && flutter test test/router_test.dart
```

기대: 5개 테스트 모두 PASS.

- [ ] **Step 10: 기본 위젯 테스트 정리**

`flutter create`가 만든 `app/test/widget_test.dart`는 삭제한다. 카운터 앱 템플릿을 검사하는 테스트라 이제 실패한다.

```bash
rm app/test/widget_test.dart
```

- [ ] **Step 11: `main.dart` 작성**

`app/lib/main.dart` 전체를 아래로 교체한다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'router.dart';

void main() {
  runApp(
    ProviderScope(
      child: TravelFootstepsApp(router: createRouter(isLoggedIn: false)),
    ),
  );
}
```

Firebase 초기화는 Task 8에서 붙인다. 지금은 로그인 화면이 뜨는 것까지만 확인한다.

- [ ] **Step 12: 전체 검사 실행**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 테스트 전부 PASS.

- [ ] **Step 13: 커밋**

```bash
git add app/
git commit -m "feat(app): Flutter 스켈레톤과 6탭 라우팅"
```

---

### Task 8: AuthRepository 추상화와 Google 로그인

**Files:**
- Create: `app/lib/core/auth/app_user.dart`
- Create: `app/lib/core/auth/auth_repository.dart`
- Create: `app/lib/core/auth/firebase_auth_repository.dart`
- Create: `app/lib/core/auth/auth_providers.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/android/app/build.gradle`, `app/android/build.gradle`
- Test: `app/test/auth/fake_auth_repository.dart`
- Test: `app/test/auth/auth_state_test.dart`

**Interfaces:**
- Consumes: Task 2의 `google-services.json`, Task 7의 `createRouter`
- Produces:
  - `AppUser` — `final String uid; final String? displayName; final String? photoUrl; final String? email;`
  - `abstract class AuthRepository` — `Stream<AppUser?> authStateChanges()`, `Future<AppUser> signInWithGoogle()`, `Future<void> signOut()`, `Future<String?> currentIdToken()`
  - `authRepositoryProvider` (Riverpod `Provider<AuthRepository>`), `authStateProvider` (`StreamProvider<AppUser?>`)
  - Task 9의 `ApiClient`가 `currentIdToken()`을 호출한다. Plan D(채팅)가 `authStateProvider`로 현재 사용자를 얻는다.

> **스펙 §3 규칙**: 화면은 `signInWithGoogle()`을 직접 부르지 않고 이 repository를 경유한다. `displayName`, `photoUrl`, `email`은 전부 nullable이다 — 이메일 가입 사용자에게는 없기 때문이다.

- [ ] **Step 1: 모델과 인터페이스 작성**

`app/lib/core/auth/app_user.dart`:

```dart
class AppUser {
  const AppUser({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.email,
  });

  final String uid;

  /// 로그인 수단에 따라 없을 수 있다. 이메일/비밀번호 가입 사용자는 null이다.
  final String? displayName;
  final String? photoUrl;
  final String? email;

  /// 표시용 이름. 없으면 uid 앞 6자로 대체한다.
  String get displayLabel =>
      (displayName != null && displayName!.isNotEmpty)
          ? displayName!
          : '여행자 ${uid.substring(0, 6)}';
}
```

`app/lib/core/auth/auth_repository.dart`:

```dart
import 'app_user.dart';

abstract class AuthRepository {
  /// 로그인 상태 변화를 방출한다. 로그아웃 상태에서는 null.
  Stream<AppUser?> authStateChanges();

  Future<AppUser> signInWithGoogle();

  Future<void> signOut();

  /// 서버 호출에 붙일 Firebase ID Token. 로그아웃 상태면 null.
  Future<String?> currentIdToken();
}
```

- [ ] **Step 2: 테스트용 가짜 구현 작성**

`app/test/auth/fake_auth_repository.dart`:

```dart
import 'dart:async';

import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  String? _idToken;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    _current = const AppUser(uid: 'uid-123', displayName: '테스터', email: 't@example.com');
    _idToken = 'valid-token';
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _idToken = null;
    _controller.add(null);
  }

  @override
  Future<String?> currentIdToken() async => _idToken;

  void dispose() => _controller.close();
}
```

- [ ] **Step 3: 실패하는 테스트 작성**

`app/test/auth/auth_state_test.dart`:

```dart
import 'package:app/core/auth/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  group('AppUser', () {
    test('displayName이 있으면 그대로 쓴다', () {
      const user = AppUser(uid: 'abcdef123', displayName: '조영진');
      expect(user.displayLabel, '조영진');
    });

    test('displayName이 null이면 uid 기반 이름으로 대체한다', () {
      const user = AppUser(uid: 'abcdef123');
      expect(user.displayLabel, '여행자 abcdef');
    });

    test('displayName이 빈 문자열이어도 대체한다', () {
      const user = AppUser(uid: 'abcdef123', displayName: '');
      expect(user.displayLabel, '여행자 abcdef');
    });
  });

  group('AuthRepository 계약', () {
    late FakeAuthRepository repo;

    setUp(() => repo = FakeAuthRepository());
    tearDown(() => repo.dispose());

    test('초기 상태는 로그아웃이다', () async {
      expect(await repo.authStateChanges().first, isNull);
      expect(await repo.currentIdToken(), isNull);
    });

    test('로그인하면 사용자와 토큰이 생긴다', () async {
      final user = await repo.signInWithGoogle();

      expect(user.uid, 'uid-123');
      expect(await repo.currentIdToken(), 'valid-token');
    });

    test('로그아웃하면 스트림이 null을 방출한다', () async {
      await repo.signInWithGoogle();
      final future = repo.authStateChanges().firstWhere((u) => u == null);

      await repo.signOut();

      expect(await future, isNull);
      expect(await repo.currentIdToken(), isNull);
    });
  });
}
```

- [ ] **Step 4: 테스트 실행하여 통과 확인**

```bash
cd app && flutter test test/auth/auth_state_test.dart
```

기대: PASS. Step 1에서 인터페이스와 모델을 이미 만들었으므로 통과한다. 이 테스트는 **`AppUser`의 nullable 처리 규칙이 깨지지 않게 지키는 회귀 테스트**다.

- [ ] **Step 5: Firebase 구현체 작성**

`app/lib/core/auth/firebase_auth_repository.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import 'app_user.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({fb.FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  Future<AppUser> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw AuthCancelledException();
    }
    final googleAuth = await googleUser.authentication;
    final credential = fb.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    final user = _toAppUser(result.user);
    if (user == null) {
      throw AuthCancelledException();
    }
    return user;
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<String?> currentIdToken() async => _auth.currentUser?.getIdToken();

  AppUser? _toAppUser(fb.User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      email: user.email,
    );
  }
}

class AuthCancelledException implements Exception {
  @override
  String toString() => '로그인이 취소되었습니다';
}
```

- [ ] **Step 6: Riverpod provider 작성**

`app/lib/core/auth/auth_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_user.dart';
import 'auth_repository.dart';
import 'firebase_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});
```

- [ ] **Step 7: Android 빌드 설정에 Google Services 플러그인 추가**

`app/android/build.gradle`의 `buildscript { dependencies { ... } }`에 추가한다. 해당 블록이 없으면 파일 상단에 만든다.

```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.2'
    }
}
```

`app/android/app/build.gradle` 상단 플러그인 목록에 추가한다.

```gradle
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"
}
```

같은 파일 `defaultConfig`의 `minSdk`를 확인한다. `firebase_auth`는 최소 23을 요구한다.

```gradle
    defaultConfig {
        applicationId "com.travelfootsteps.app"
        minSdk 23
        targetSdk flutter.targetSdkVersion
        versionCode flutter.versionCode
        versionName flutter.versionName
    }
```

- [ ] **Step 8: `main.dart`에 Firebase 초기화와 인증 연결**

`app/lib/main.dart` 전체를 아래로 교체한다.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_providers.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: _Root()));
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(body: Center(child: Text('인증 오류: $e'))),
      ),
      data: (user) => TravelFootstepsApp(
        router: createRouter(
          isLoggedIn: user != null,
          onSignIn: () => ref.read(authRepositoryProvider).signInWithGoogle(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: 실기기 또는 에뮬레이터에서 로그인 확인**

```bash
cd app && flutter run
```

확인 항목:
1. 로그인 화면이 뜬다
2. "Google로 계속하기"를 누르면 계정 선택 다이얼로그가 뜬다
3. 계정 선택 후 **비자 탭**으로 이동한다
4. 하단 6개 탭을 눌러 각각 '비자', '준비물', '발걸음', '그룹', '번역', '주변'이 표시된다

> 로그인 후 아무 일도 일어나지 않으면 **SHA-1 미등록**이 원인이다. Task 2 Step 3에서 자신의 디버그 SHA-1을 Firebase 콘솔에 등록했는지 확인한다.

- [ ] **Step 10: 전체 검사 실행**

```bash
cd app && flutter analyze && flutter test
```

기대: 전부 PASS.

- [ ] **Step 11: 커밋**

```bash
git add app/lib app/test app/android app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): AuthRepository 추상화와 Google 로그인"
```

`git status`에 `google-services.json`이 없는지 확인한다.

---

### Task 9: 앱과 서버 연결 — M1 게이트

**Files:**
- Create: `app/lib/core/network/api_client.dart`
- Create: `app/lib/core/network/country_api.dart`
- Modify: `app/lib/features/checklist/checklist_page.dart`
- Test: `app/test/network/api_client_test.dart`

**Interfaces:**
- Consumes: Task 6의 `GET /api/countries`, Task 8의 `AuthRepository.currentIdToken()`
- Produces:
  - `apiClientProvider` (Riverpod `Provider<Dio>`) — 모든 서버 호출이 이 인스턴스를 쓴다. 토큰 인터셉터가 붙어 있으므로 개별 호출에서 헤더를 붙이지 않는다.
  - `Country` (앱 모델) — `isoAlpha2`, `nameKo`, `nameEn`, `continent`, `tier`
  - `countryListProvider` (`FutureProvider<List<Country>>`)
  - Plan B~F의 모든 서버 호출이 `apiClientProvider`를 재사용한다.

- [ ] **Step 1: 실패하는 인터셉터 테스트 작성**

`app/test/network/api_client_test.dart`:

```dart
import 'dart:async';

import 'package:app/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthInterceptor', () {
    test('토큰이 있으면 Authorization 헤더를 붙인다', () async {
      final interceptor = AuthInterceptor(() async => 'valid-token');
      final options = RequestOptions(path: '/api/countries');
      final handler = _CaptureRequestHandler();

      interceptor.onRequest(options, handler);
      await handler.done;

      expect(handler.captured!.headers['Authorization'], 'Bearer valid-token');
    });

    test('토큰이 없으면 헤더를 붙이지 않는다', () async {
      final interceptor = AuthInterceptor(() async => null);
      final options = RequestOptions(path: '/api/countries');
      final handler = _CaptureRequestHandler();

      interceptor.onRequest(options, handler);
      await handler.done;

      expect(handler.captured!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('resolveBaseUrl', () {
    test('안드로이드에서는 에뮬레이터 호스트 주소를 쓴다', () {
      expect(resolveBaseUrl(isAndroid: true), 'http://10.0.2.2:8080');
    });

    test('그 외에서는 localhost를 쓴다', () {
      expect(resolveBaseUrl(isAndroid: false), 'http://localhost:8080');
    });
  });
}

class _CaptureRequestHandler extends RequestInterceptorHandler {
  RequestOptions? captured;
  final _completer = Completer<void>();

  Future<void> get done => _completer.future;

  @override
  void next(RequestOptions requestOptions) {
    captured = requestOptions;
    _completer.complete();
  }
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/network/api_client_test.dart
```

기대: 컴파일 실패 — `app/core/network/api_client.dart`를 찾을 수 없음.

- [ ] **Step 3: API 클라이언트 구현**

`app/lib/core/network/api_client.dart`:

```dart
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';

typedef TokenSupplier = Future<String?> Function();

/// 매 요청마다 Firebase ID Token을 Authorization 헤더에 붙인다.
/// 토큰은 만료되므로 캐시하지 않고 매번 가져온다 (SDK가 내부적으로 캐시한다).
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenSupplier);

  final TokenSupplier _tokenSupplier;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _tokenSupplier().then((token) {
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }).catchError((_) {
      handler.next(options);
    });
  }
}

String resolveBaseUrl({required bool isAndroid}) =>
    isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';

final apiClientProvider = Provider<Dio>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  final dio = Dio(BaseOptions(
    baseUrl: resolveBaseUrl(isAndroid: Platform.isAndroid),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  dio.interceptors.add(AuthInterceptor(authRepository.currentIdToken));
  return dio;
});
```

> `10.0.2.2`는 안드로이드 에뮬레이터에서 호스트 PC를 가리키는 주소다. **실기기로 테스트할 때는 PC의 LAN IP로 바꿔야 한다.** 배포 시에는 서버 도메인으로 교체한다.

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/network/api_client_test.dart
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 5: 국가 API 클라이언트 작성**

`app/lib/core/network/country_api.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class Country {
  const Country({
    required this.isoAlpha2,
    required this.nameKo,
    this.nameEn,
    this.continent,
    required this.tier,
  });

  final String isoAlpha2;
  final String nameKo;
  final String? nameEn;
  final String? continent;
  final String tier;

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        isoAlpha2: json['isoAlpha2'] as String,
        nameKo: json['nameKo'] as String,
        nameEn: json['nameEn'] as String?,
        continent: json['continent'] as String?,
        tier: json['tier'] as String,
      );
}

final countryListProvider = FutureProvider<List<Country>>((ref) async {
  final dio = ref.watch(apiClientProvider);
  final Response<List<dynamic>> response = await dio.get('/api/countries');
  return response.data!
      .map((e) => Country.fromJson(e as Map<String, dynamic>))
      .toList();
});
```

- [ ] **Step 6: 준비물 탭에서 국가 목록을 표시**

M1 게이트를 눈으로 확인하기 위한 임시 화면이다. Plan B에서 실제 준비물 화면으로 교체한다.

`app/lib/features/checklist/checklist_page.dart` 전체를 아래로 교체한다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/country_api.dart';

class ChecklistPage extends ConsumerWidget {
  const ChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(countryListProvider);

    return countries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('국가 목록을 불러오지 못했습니다\n$e', textAlign: TextAlign.center),
        ),
      ),
      data: (list) => ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) => ListTile(
          title: Text(list[i].nameKo),
          subtitle: Text(list[i].nameEn ?? '-'),
          trailing: Text('Tier ${list[i].tier}'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: M1 게이트 확인 — 앱과 서버를 함께 실행**

터미널 1 (PostgreSQL이 떠 있어야 한다):

```bash
cd server && ./gradlew bootRun
```

터미널 2:

```bash
cd app && flutter run
```

**M1 게이트 통과 조건:**
1. 로그인 화면 → Google 로그인 성공
2. 비자 탭으로 이동
3. 하단 6개 탭이 모두 동작
4. **준비물 탭에서 20개국 목록이 표시된다** ← 앱↔서버↔DB 전 구간이 연결됐다는 증거

> 준비물 탭에서 401 오류가 나면 토큰이 헤더에 안 붙은 것이다. 서버 로그에서 `토큰 검증 실패`를 찾아본다. 연결 자체가 안 되면 `10.0.2.2` 주소와 서버가 8080에서 떠 있는지 확인한다.

- [ ] **Step 8: 전체 검사 실행**

```bash
cd app && flutter analyze && flutter test
cd ../server && ./gradlew test
```

기대: 양쪽 모두 PASS.

- [ ] **Step 9: 커밋과 PR**

```bash
git add app/lib/core/network app/test/network app/lib/features/checklist
git commit -m "feat(app): API 클라이언트와 국가 목록 연동 (M1 게이트)"
git push origin HEAD
```

`develop`으로 PR을 올리고 2인 승인을 받는다. CI의 `Flutter`, `Spring Boot` job이 모두 초록인지 확인한다.

---

## M1 게이트 체크리스트

Phase 0 완료 판정 기준이다. 전부 만족해야 Phase 1로 넘어간다.

- [ ] 공공데이터포털 인증키로 입국허가요건 API 호출이 성공한다
- [ ] Firebase 프로젝트가 있고 **팀원 4명 모두** 자기 SHA-1을 등록해 로그인이 된다
- [ ] GCP 예산 알림 $10이 설정되어 있다
- [ ] `develop` 브랜치 보호 규칙이 켜져 있고 CI 2개 job이 초록이다
- [ ] 앱: Google 로그인 후 6개 탭 이동이 된다
- [ ] 서버: `GET /api/health`가 200, 토큰 없는 `GET /api/countries`가 401
- [ ] 앱 준비물 탭에서 서버가 준 20개국 목록이 보인다
- [ ] 저장소에 `google-services.json`, `firebase-service-account.json`, `.env`가 커밋되지 않았다

마지막 항목은 아래로 확인한다.

```bash
git ls-files | grep -E 'google-services|service-account|\.env'
```

기대: 출력 없음.

---

## 다음 계획서

Phase 0 완료 후 각 담당이 자기 계획서로 갈라진다. 계획서는 각 Phase 착수 시점에 작성한다.

| 계획서 | 담당 | 시기 | 선행 |
|---|---|---|---|
| Plan A — 서버: 공공데이터 파이프라인 + 비자 규칙 엔진 | R1 | W3~7 | Task 4, 6 |
| Plan B — 앱: 여행계획·비자 화면·로컬 알람·준비물 | R2, R4 | W3~6 | Task 8, 9 + Plan A의 판정 API |
| Plan C — 앱: 지도·발걸음·위치공유 | R3 | W3~7 | Task 9 |
| Plan D — 앱: 채팅 (그룹→DM→사진→읽음) | R2 | W6~9 | Task 8 |
| Plan E — 앱: 번역 3종 | R4 | W6~9 | Task 9 + Plan A의 번역 프록시 |
| Plan F — 앱: 주변 여행 정보 | R3 | W9~10 | Plan C |
