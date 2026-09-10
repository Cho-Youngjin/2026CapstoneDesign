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
