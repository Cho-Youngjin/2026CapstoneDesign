# 경로 복원 API 안내 (R5)

재생기가 남긴 드문 점(`fixes.csv`)과 머문 곳(`stays.csv`)을 도로 위 경로로 복원한다. 설계는 `docs/superpowers/specs/2026-11-07-footstep-research-implementation-design.md` 6장이다. 앱의 날짜별 보기(R7)와 R6 분석이 같은 API를 쓴다.

## 1. 로컬 OSRM 띄우기

Docker Desktop을 켠 뒤 저장소 루트에서:

```bash
cd osrm
./setup.sh                 # 최초 1회 — 한국 OSM 데이터 다운로드 + 도보 프로필 전처리
docker compose up -d osrm  # http://localhost:5001
curl "http://localhost:5001/nearest/v1/foot/126.9780,37.5665?number=5"   # code: "Ok"면 정상
```

복원은 OSRM의 `/nearest`·`/table`·`/route`·`/match`를 쓴다. 도보 프로필이라 버스 구간은 걸을 수 있는 길로 이어진다(설계 10장 위험 5).

## 2. 서버를 local 프로필로 띄우기

`local` 프로필은 Firebase 없이 더미 토큰 `dev-fake-token`만 받는다(`LocalDevTokenVerifier`). PostgreSQL(5432)은 평소처럼 떠 있어야 한다.

```bash
cd server
OSRM_BASE_URL=http://localhost:5001 SPRING_PROFILES_ACTIVE=local SERVER_PORT=9090 ./gradlew bootRun
```

이 PC는 Windows가 포트 범위를 예약해 8080을 못 쓸 때가 있다. `netsh interface ipv4 show excludedportrange protocol=tcp`로 비어 있는 포트를 골라 `SERVER_PORT`에 넣는다.

## 3. 호출하기

```bash
curl -s -X POST http://localhost:9090/api/route/reconstruct \
  -H "Authorization: Bearer dev-fake-token" -H "Content-Type: application/json" \
  -d '{"method":"hmm_steps",
       "points":[{"t":1762480000000,"lat":37.5665,"lng":126.9780,"accuracy":8.0,"stepsSincePrev":null,"state":"walking"},
                 {"t":1762480060000,"lat":37.5670,"lng":126.9790,"accuracy":10.0,"stepsSincePrev":120,"state":"walking"}],
       "stays":[],
       "hmm":{"betaM":10,"sigmaMinM":5}}'
```

- `points`: `fixes.csv`의 행을 그대로 옮긴다(`t_ms`→`t`, `accuracy_m`→`accuracy`, `steps_since_prev`→`stepsSincePrev`, `state`). 최대 2000개, 대상 국가는 KR 고정이다.
- `stays`: `stays.csv`의 행(`arrive_ms`→`arrive`, `leave_ms`→`leave`, `lat`, `lng`). 최대 500개. 빼도 된다.
- `method`: 빼면 앱 기본값 `osrm_match_radius`다.
- 응답: `{"method": …, "segments": [{"kind": "walk|vehicle|estimated", "coords": [{"lat","lng"}…], "fallback": false}]}`

## 4. 복원 방법

| method | 내용 |
|---|---|
| `straight` | 점을 직선으로 잇는다 |
| `nearest` | 점마다 200m 안의 가장 가까운 도로에 붙인 뒤 직선으로 잇는다 |
| `osrm_match` | OSRM `/match` 기본값(GPS 표준편차 5m) |
| `osrm_match_radius` | `/match`에 점 정확도를 5~50m로 맞춘 `radiuses`와 초 단위 `timestamps`를 넘긴다(**앱 기본값**) |
| `hmm_steps` | **제안**. Newson & Krumm(2009) HMM의 전이 확률에 걸음 수 × 보폭을 쓴다. 후보는 200m 안의 도로 위 점 5개, 고른 후보 사이는 `/route`로 잇는다 |

처리 순서는 모든 방법이 같다.
1. 머문 곳 시간 범위 안의 점을 그 중심 하나로 바꾼다.
2. 앞 점(머문 곳이면 출발 시각)에서 다음 점까지 10분 이상 비면 자르고, 그 사이는 `/route`로 이어 `estimated`로 표시한다.
3. 나머지를 방법대로 잇는다. 탈것 상태(`state: vehicle`)로 도착한 점까지는 `vehicle`, 그 밖은 `walk` 구간이다.

OSRM이 꺼져 있거나 매칭에 실패한 조각은 직선으로 채우고 `fallback: true`를 붙인다. `hmm_steps`는 도로가 200m 안에 없는 점에서 끊긴 곳만 직선이다.

## 5. `hmm_steps` 조정값 (`hmm`)

| 이름 | 기본값 | 뜻 |
|---|---|---|
| `betaM` | 10 | 전이 확률 exp(−\|도로 경로거리 − 걸은 거리\| / β)의 β(m). OSRM 자체 맵 매칭의 기본값과 같다 |
| `sigmaMinM` | 5 | 방사 확률 σ의 하한(m). σ = max(점 정확도, 하한) |
| `strideM` | 0.75 | 걸은 거리 = 걸음 수 × 보폭 |
| `useSteps` | true | false면 걸은 거리 대신 두 점의 직선거리(Newson & Krumm 원래 식, 절제 실험) |

**β와 σ 하한은 R6에서 예비용(pilot) 세션으로만 정한다.** Newson & Krumm은 정답 경로에서 β = median\|직선거리 − 도로 경로거리\| / ln 2, σ = 1.4826 × median\|점 − 정답 도로 점\|로 추정했다(원문 식 5·6). 원문은 성능을 최대로 하는 값을 찾는 것을 후속 과제로 남겼다. 이 연구는 예비용 세션에서 β ∈ {2, 5, 10, 20, 50}m, σ 하한 ∈ {3, 5, 10}m를 격자로 바꿔 경로 오차 P95가 가장 작은 값을 고르고, 평가용 세션에는 그 값만 쓴다.

## 6. 해석할 때 주의

- `stepsSincePrev`는 재생기가 끝에 걸음 시각으로 다시 센 값이다. 폰 정책 실행 모드의 `fixes.csv`와 앱 여행 기록(R7)은 걷기 시작 몇 초 안의 측위에서 걸음 몇 개가 빠질 수 있다. 앱의 날짜별 보기는 기본 방법(`osrm_match_radius`)이라 이 값을 경로에 쓰지 않고, 그날 걸음 수 합만 그만큼 모자랄 수 있다.
- 도보 프로필이라 `vehicle` 구간도 걸을 수 있는 길로 이어진다. 탈것 구간 오차는 따로 보고한다.
- `osrm_match_radius`는 시각을 함께 넘기므로 `gaps=ignore`를 보낸다. 드문 측위(수십 초~수 분 간격)에서 OSRM이 시각 간격이 크다고 궤적을 쪼개지 않게 하려는 것이다. 그래도 전이가 불가능해 나뉜 조각은 직선으로 이어 붙는다.
- 머문 곳 중심은 정확도를 반경 상한(50m)으로 보낸다. 건물 안에서 평균 낸 중심이 도로에서 떨어져 있어도 매칭에서 버려지지 않게 하려는 것이다.
- 복원 결과와 세션 데이터(`research/`)는 커밋하지 않는다.
