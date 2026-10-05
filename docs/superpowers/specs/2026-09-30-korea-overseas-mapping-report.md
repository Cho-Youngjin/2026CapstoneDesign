# 한국 → 해외 매핑 — 구현 보고서

**작성일** 2026-09-30
**관련 브랜치** `feature/footsteps-realtime`
**관련 문서** 초기 설계 `docs/superpowers/specs/2026-09-29-overseas-footsteps-route-projection.md`, OSRM 인프라 `osrm/README.md`, 실행 방법 `HowToTest.md`
**성격** 보고서 겸 구현 정리 겸 설명 문서. 무엇을 만들었고, 어떤 문제를 겪었고, 어떻게 바꿨고, 결과가 어떤지 한 곳에 모은다.

> **2026-10-04 갱신:** 이 문서의 서버 내용은 `mock-server/mock_server.py` 기준으로 쓰였다. 같은 로직을 Spring 서버(`server/.../route/`)로 이관했다(§7.1). 이관 대상은 2차 구현(도로 위 걷기)과 앵커 검증, 도로 스냅이다. 1차의 `/api/route/overseas-snap`은 앱이 쓰지 않아 옮기지 않았다. `mock-server/mock_server.py`는 이제 git에 보관되며(`.env`만 무시), R1 서버 없이 R3만 검증할 때 쓴다. 알고리즘을 고칠 때는 두 구현을 함께 맞춰야 한다.

---

## 1. 한눈에 보기

**하려던 것.** 사용자가 한국에서 걸어도, 그 이동을 일본의 실제 도로 위에서 걷는 것처럼 지도에 보여 준다. 물리적으로 해외에 가지 못해도 "해외에 있는 것과 비슷한 경험"을 국내에서 재현하는 기능이다.

**만든 것.**
- 일본(간토) 도로망을 담은 OSRM 서버와, 한국 이동을 일본 도로 위의 걸음으로 옮기는 mock 서버 로직
- 앱의 검증용 화면 **[해외 매핑 테스트]**: 왼쪽은 한국 실제 이동, 오른쪽은 일본에 옮긴 경로

**두 번의 구현.**

| | 1차 (합성 좌표 + `/match`) | 2차 (도로 위 걷기, 현재) |
|---|---|---|
| 발상 | 한국의 방향·거리를 일본 좌표에 겹쳐 놓고 가장 가까운 도로에 붙임 | 일본 위치를 항상 도로 위에 두고, 한국에서 걸은 거리만큼 도로를 따라 걸음 |
| 잘 되는 경우 | 한국과 일본 도로가 비슷한 방향일 때 | 대부분의 경우 |
| 문제 | 갈림길 U턴, 막다른 길 정지, 도로 밖 확정 | 막다른 길 진입이 잦음, 후보 조회 수 증가 |

**핵심 결과 (도쿄 시뮬레이션).**
- 180° 급반전(60곳, 한국 직진 400m): 19회 → 3회 (경로 끝 정리까지 적용한 시점 기준)
- 조용한 정지, 호출 실패 연쇄, 도로 밖 확정: 모두 0
- 한국 이동 방향과의 편차(실제 굽은 경로 30곳, 중앙값): 85° → 19° (이상 위치 가중치 3 적용 시)

측정 조건과 세부 수치는 [6장](#6-검증-결과)에 있다. 최종 설정(가중치 3)에서 60곳 전체의 반전 횟수는 다시 재지 않았고, 40곳 800m 직진에서 반전 4회, `deadEnd` 2회, 실패 0곳으로 확인했다.

---

## 2. 배경과 목표

- 지도교수 면담 피드백(2026-09): 현실성보다 기술 완성도와 API 다양성을 우선하고, 해외에 못 가도 국내에서 해외 경험을 재현하는 방향.
- 데모 대상국은 **일본**으로 확정(2026-09-29). 도쿄를 포함한 **간토 지역**만 OSRM 데이터로 처리한다.
- 원칙: OSRM만으로 스코프 안에서 구현한다. 유료 API(Google Roads 등)는 쓰지 않는다. Google Roads는 한국 도로 데이터를 아예 갖고 있지 않아 이미 OSRM으로 교체한 바 있다(`osrm/README.md`).
- 이 기능이 그린 경로는 체크인이나 RoutePoint로 **저장하지 않는다**. 검증용 별도 세션이다.

---

## 3. 전체 구조

```
[앱: 해외 매핑 테스트 화면]                          [mock 서버 :8080]                       [OSRM]
 ├ 위치 스트림(10m 간격)                               ├ /api/route/overseas-anchor/validate ──▶ 일본 :5002 /nearest
 ├ 누적 50m마다 요청  ── points, anchor, state ──▶    └ /api/route/overseas-walk            ──▶ 일본 :5002 /route (후보 8개)
 └ 응답 경로를 오른쪽 지도에 이어 그림  ◀── matched, newAnchor, state, event ──
```

| 구성요소 | 위치 | 역할 |
|---|---|---|
| OSRM 한국 인스턴스 | `:5001` | 국내 도로 스냅(기존). 시뮬레이션에서 한국 도보 경로 생성에도 사용 |
| OSRM 일본 인스턴스 | `:5002`, `osrm/setup-japan.sh` | 간토 지역 도보 프로필 |
| mock 서버 | `mock-server/mock_server.py` | 해외 매핑 계산 전부(R1 서버 없이 검증할 때) |
| Spring 서버 | `server/.../route/` | 같은 계산의 정식 구현. 앱 계약은 mock과 동일 |
| 앱 API 클라이언트 | `overseas_mapping_api.dart` | 앵커 검증, 걷기 요청 |
| 출발점 선택 팝업 | `overseas_anchor_picker_dialog.dart` | 지도 탭 → 도로 검증 → 도로에 붙인 좌표 반환 |
| 테스트 화면 | `overseas_mapping_test_page.dart` | 좌/우 분할 지도, 트리거, 마커·화살표 |

**앱이 서버를 호출하는 규칙.**
- 위치 스트림은 `distanceFilter: 10`(10m 이동마다 이벤트)이다.
- 마지막 요청 이후 누적 이동 거리가 **50m**를 넘으면 서버를 호출한다.
- 요청이 실패하면 카운터를 리셋하지 않고 다음 트리거에서 더 긴 구간으로 다시 시도한다.

---

## 4. 1차 구현: 합성 좌표 + `/match`

### 4.1 알고리즘

한국 이동을 절대 좌표가 아니라 "어느 방향으로 얼마나 갔는가"로만 본다.

1. **거리** (하버사인): 인접한 두 한국 점 `(φ₁, λ₁) → (φ₂, λ₂)`에서
   `a = sin²(Δφ/2) + cosφ₁·cosφ₂·sin²(Δλ/2)`, `d = 2R·asin(√a)` (`R = 6,371,000 m`)
2. **방향** (초기 방위각): `θ = atan2( sinΔλ·cosφ₂ , cosφ₁·sinφ₂ − sinφ₁·cosφ₂·cosΔλ )`
3. **일본 쪽 이동** (구면 삼각법): 일본 현재 위치에서 방향 `θ`로 거리 `d`만큼 이동한 점
   `φ₂' = asin( sinφ₁·cos(d/R) + cosφ₁·sin(d/R)·cosθ )`
   `λ₂' = λ₁ + atan2( sinθ·sin(d/R)·cosφ₁ , cos(d/R) − sinφ₁·sinφ₂' )`
4. 이렇게 이어 붙인 **합성 좌표**(도로 위라는 보장 없음)를 일본 OSRM의 `/match/v1/foot/...`에 보내 도로 위 경로로 맞춘다.
5. 매칭 결과의 마지막 점이 새 anchor가 되고, 이후 구간은 그 anchor에서 다시 시작한다.
6. 300m 넘게 매칭이 실패하면 합성 좌표를 그대로 돌려주고 "도로 밖"으로 표시했다(회색 점선).

### 4.2 1차 구현에서 고친 것들

| 문제 | 원인 | 조치 | 결과 |
|---|---|---|---|
| 일본 지도가 도중에 서울로 바뀜 | 앱이 다음 구간의 첫 좌표를 **직전 한국 좌표가 아니라 일본 anchor**로 채우고 있었다. 서버가 "도쿄→서울 1,150km 이동"으로 계산해 anchor가 서울로 튐 | 다음 구간 첫 좌표를 방금 보낸 구간의 마지막 한국 좌표로 수정 | 서울로 튀는 현상 사라짐 |
| 앵커 검증이 항상 실패 | 오래 떠 있던 mock 서버가 일본 OSRM 주소(`OSRM_BASE_URL_JP`)를 읽지 못한 상태였다 | 서버 재시작 | 도쿄 좌표 통과, 서울 좌표 거부 |
| 경로가 짧아지고 옆길로 튐 | OSRM `/match` 기본 반경(5m). 합성 좌표는 일본 도로와 방향이 안 맞아 도로에서 벗어나기 쉬운데, 5m 밖의 점은 버려진다 | 점마다 `radiuses=30`(m) 지정 | 아래 표 |

**매칭 반경 효과** (서울역→시청역 실제 도보 경로 1,344m, 일본 임의 출발점):

| | 5m(기본) | 30m |
|---|---|---|
| 서버 호출 | 29회 | 24회 |
| 실패한 호출 | 6회 | 0회 |
| 버려진 점 | 45 / 145개 (31%) | 0개 |
| 한국 이동 대비 일본 경로 길이 | 78% | 91% |

### 4.3 테스트 절차에서 알게 된 것: GPS 순간이동

에뮬레이터는 시작할 때 **이전 위치**를 첫 GPS 값으로 내보낸 뒤 새 위치로 점프하는 것으로 보인다(시뮬레이션과 화면의 증상이 모두 이 설명과 맞는다). 앱은 이 점프를 걸음(약 575m)으로 착각한다. 300m를 넘어 "도로 밖" 구간이 되고, 주황 경로는 그 구간을 건너뛰고 이어 그리는 탓에 **출발점에서 새 시작점까지 곧은 선**이 생겼다. 실제 폰에서도 GPS가 한동안 끊겼다가 멀리서 잡히면 같은 일이 생길 수 있다.

**조치:** 코드로 막지는 않았다. 테스트할 때 에뮬레이터 위치를 걷기 시작 좌표로 **먼저** 맞춰 두고 시작하는 절차로 피했다. 비현실적인 속도의 점을 버리는 방어는 남은 과제다([8장](#8-한계와-남은-과제)).

---

## 5. 구조적 한계의 발견과 2차 구현

### 5.1 재현 실험

1차 방식은 한국 이동의 **모양**만 겹쳐서 가까운 도로에 붙일 뿐, 일본 도로망을 따라 걷는다는 개념이 없다. 이 때문에 생기는 문제를, 도쿄 도로 위 무작위 출발점 60곳에서 한국이 도로 방향으로 **완전한 직진**을 하게 해서 재현했다. 앱의 트리거 규칙과 실제 mock 서버를 그대로 썼다.

**(1) 갈림길에서 방향이 계속 뒤집힘** (한국은 직진, 일본은 정면에 길이 없음)
- 60곳 중 52곳은 정상이었고 8곳이 이상했다(왕복·우회 의심 6곳, 정지·실패 3곳, 중복 1곳).
- 대표 사례 #6: 한국은 방위 283°로 직진했지만 일본 경로는 요청마다 방향이 49°, 51° 틀어지고, 출발 후 304m·377m·450m 지점에서 각각 -178°, 180°, -180°로 **정반대 U턴**을 반복했다. 경로 길이 525m에 직선 거리는 191m였다.
- 원인: 정면에 길이 없으면 좌우 갈래가 비슷한 거리이고, 어느 쪽에 붙을지는 그때그때 계산에 따라 정해진다. 이전 선택을 기억하지 않아서 다음 요청에서 반대편으로 붙을 수 있다.

**(2) 막다른 길** (한국 800m 직진)
- 7곳(약 12%)에서 문제가 났다.
- **조용한 정지(#35):** 13번 호출이 모두 성공인데 후반 4번이 0m 전진. 앱이 이상을 알아챌 수 없다.
- **느린 기어감(#43):** 후반 4번이 각각 4m 전진.
- **실패 연쇄(#14, #22, #38):** 끝에서 실패가 계속 쌓이는 중.
- **도로 밖 확정(#28, #50):** 실패가 25번 쌓인 뒤 300m를 넘어 도로 밖으로 확정. #50은 이후 스스로 복귀했지만 #28은 복귀하지 못하고 0m 전진이 이어졌다.
- 도로 밖으로 확정된 위치점은 anchor가 도로에 붙지 않은 합성 좌표여서 건물 안에 서 있게 된다.

**(3) 방향·거리 차이가 큰 경우**
- 한국 진행 방향을 도로 방향에서 Δ만큼 어긋나게 400m 직진(30곳):

| Δ | 직선 변위 ÷ 한국 거리(중앙값) | 실패 | 도로 밖 |
|---|---|---|---|
| 0° | 0.87 | 25/228 | 1곳 |
| 30° | 0.78 | 25/225 | 1곳 |
| 45° | 0.71 | 25/223 | 1곳 |
| 60° | 0.74 | 26/223 | 1곳 |
| 90° | 0.82 | 0/202 | 0곳 |

- 방향 차이가 클수록 무조건 나빠지는 구조는 아니었다. 실패와 도로 밖은 Δ와 무관하게 거의 같아서 특정 출발점에서 생기는 문제로 보인다(이 해석은 검증하지 못함).
- 실제 서울역→시청역 도보(1,371m, 굽은 길)를 일본 30곳에 적용하면 일본 경로 길이 ÷ 한국 거리가 0.71~1.07(중앙값 0.99)였다. 다만 이 지표는 경로가 맞는지의 증거가 아니다. 왕복이 길이를 더할 수도 있다.

### 5.2 2차 설계: 도로 위 걷기

세 문제의 공통 원인은 "이전에 어디로 가고 있었는지 기억하지 않는다"와 "도로 위 상태가 없다"이다. 그래서 일본 위치를 **도로 위 점 + 기억**으로 다룬다. 핵심은 세 가지가 함께 있는 것이다.

| | 내용 | 해결하는 문제 |
|---|---|---|
| ① 위치는 항상 도로 위 | 도로 경로 좌표를 따라 걸어서 anchor가 항상 도로 위에 있다 | 도로 밖에 서 있는 위치점 |
| ② 기억 | 마지막 진행 방향, 지나온 길, 직전에 꺾은 쪽, 이상 위치를 요청 사이에 들고 다닌다 | 갈림길 U턴 반복 |
| ③ 선택 규칙 | 상대적 방향으로 후보를 만들고 점수로 고른다. 정면이 막히면 U턴도 정상 후보 | 갈림길, 막다른 길 |

**한 요청의 처리 (서버 `walk_overseas_segment`).**
1. **입력:** 도로 위 anchor, 한국 점들(첫 점은 직전 요청의 마지막 한국 점), 앱이 돌려준 `state`
2. **이동 거리 `d`:** 한국 점들 사이 거리의 합
3. **원하는 방향 `desired`:**
   - 첫 요청은 한국 방위 그대로
   - 이후는 `일본 마지막 진행 방향 + 한국 회전량`. 한국 회전량은 이번 요청의 한국 방위 − 직전 요청의 한국 방위이며, 10° 미만은 GPS 흔들림으로 보고 0으로 본다
4. **후보 8개:** `desired`를 기준으로 0°, ±45°, ±90°, ±135°, 180° 방향으로 `d`만큼 떨어진 점을 목적지로 잡고, 각각 OSRM `/route`로 도보 경로를 구한다
5. **경로 자르기:** 각 경로를 앞에서부터 `d`미터까지만 자른다. 끝점은 마지막 도로 선분 위를 보간한 점이라 항상 도로 위다
6. **"앞으로 가는" 후보 필터:** 실제 진행 방향이 `desired`와 100° 이내이고, `d`의 50% 이상 전진하고, 지나온 길과 절반 미만 겹치는 후보
7. **점수** (낮을수록 좋음):

```
score = 1.0 × (각도 차이 ÷ 180)
      + 2.0 × max(0, 1 − 전진량 ÷ d)
      + 1.5 × (지나온 길과 겹친 비율)
      + 3.0 × min(이상 위치까지 거리 ÷ 200m, 1.5)
      − 0.05  (직전에 꺾은 쪽과 같은 방향이면)
```

8. **막다른 길:** 앞으로 가는 후보가 하나도 없으면 되돌아가는 후보 중 가장 멀리 가는 것을 택하고 `event: "deadEnd"`를 응답한다. 이때 지나온 길 기록은 비운다(되돌아가는 길이 "지나온 길"로 감점되지 않도록)
9. **경로 끝 정리:** 잘린 끝이 교차로 옆 갈래 안쪽 15m 이내이면 그 짧은 조각을 잘라내 교차로에서 끝낸다
10. **출력:** 도로 위 경로 `matched`, 새 anchor(경로의 마지막 점), 새 `state`, `event`(`deadEnd`, `blocked`, 없음)

**이상 위치란.** 한국 이동을 그대로 일본에 옮겼다면 도착했을 위치(1차 방식의 합성 좌표와 같은 계산을 도로에 붙이지 않고 누적한 것). 도로가 꺾이는 대로만 따라가면 한국의 절대 방향에서 계속 벗어나서(예: 북동으로 가다 서북으로 꺾어 쭉 감), 갈림길에서 이 위치 쪽에 가까워지는 후보를 유리하게 하는 힘이다.

**도로 밖 상태를 없앴다.** 1차의 "300m 실패 누적 → 합성 좌표를 그대로 돌려줌" 경로는 쓰지 않는다. 모든 후보 조회가 실패하면 anchor를 그대로 두고 `event: "blocked"`만 돌려주므로 anchor는 언제나 도로 위에 있다.

### 5.3 시도했다가 되돌린 것

| 시도 | 이유 | 결과 | 조치 |
|---|---|---|---|
| OSRM `bearings` 옵션(후보 목적지를 ±60° 도로에만 붙임) | 요청 끝에서 옆 골목으로 살짝 들어갔다 나오는 짧은 U턴을 막으려고 | 400m 반전 8→**10**회, 막다른 길 진입 증가 | **되돌림** |
| 경로 끝 스퍼 자르기 | 위와 같은 짧은 U턴. 원인은 요청이 정확히 `d`미터에서 잘리면서 교차로 옆 갈래 안쪽에 서는 것이었다 | 400m 반전 8→**3**회, 800m 25→**8**회 | **적용** |
| 이상 위치 가중치 0, 1, 3, 6, 10 비교 | 방향이 한국에서 벗어나는 문제 | 아래 6.3 | **3 채택** |

---

## 6. 검증 결과

### 6.1 방법

- **출발점:** 도쿄 세타가야·시부야 일대 임의의 도로 위 60곳(`nearest` 응답이 도로 40m 이내인 곳). 재현성을 위해 무작위 시드를 고정했다.
- **한국 이동:** 그 도로 방향으로 400m 또는 800m 완전한 직진(10m 간격 점), 또는 실제 서울역→시청역 도보 경로(1.3~1.4km).
- **앱 로직 재현:** 누적 50m마다 서버 호출, 요청마다 `state` 전달, 응답의 마지막 한국 좌표로 버퍼 재시작.
- **서버:** 실제 mock 서버와 일본 OSRM을 그대로 호출.
- **반전 정의:** 8m 이상 떨어진 경로 점 사이의 진행 방향이 150° 이상 바뀐 곳.

> 시뮬레이션 스크립트는 저장소에 포함하지 않았다(세션 임시 디렉터리에서 실행). 결과를 다시 내려면 위 조건으로 새로 만들어야 한다.

### 6.2 1차 대비 2차

| 지표 (60곳) | 1차 (반경 30m 적용) | 2차, 400m ※ | 2차, 800m ※ |
|---|---|---|---|
| 180° 급반전 횟수 | 19회 (9곳) | **3회** (막다른 길 2 + 그 외 1) | **8회** (막다른 길 5 + 경계 2 + 그 외 1) |
| 조용한 정지 | 있음(#35, #43) | **0** | **0** |
| 호출 실패, `blocked` | 다수 | **0** | **0** |
| 도로 밖 확정 | 있음(#28, #50 등) | **없음** | **없음** |
| `deadEnd` 감지 | 감지 못 함 | 2곳 | 6곳 |
| 직선 변위 ÷ 한국 거리(중앙값) | 0.86 | 0.75 | 0.73 |

- ※ 2차 열은 **경로 끝 정리(스퍼 자르기)까지 적용하고 이상 위치를 넣기 전** 측정값이다. 이상 위치(가중치 3)를 넣은 최종 설정에서는 60곳 전체를 다시 재지 않았다. 대신 40곳 800m 직진에서 반전 4회, `deadEnd` 2회, 실패 0곳(6.3 표)으로 확인했다.
- 1차의 800m 반전 횟수는 같은 조건으로 재측정하지 않았다(400m만 비교).
- 남은 반전 중 막다른 길 U턴은 의도된 동작이다. 나머지(400m 1회 등)는 원인을 확인하지 못했다.
- 직선 변위 ÷ 한국 거리는 2차가 조금 낮다. 길을 따라 굽어 가기 때문일 수 있지만, 이 지표는 정확도가 아니라서 좋고 나쁨은 판단하지 못했다.

### 6.3 이상 위치 가중치 선정

| 가중치 | 직진 800m(40곳) 편차 중앙값 | 실제 경로 1.37km(30곳) 편차 중앙값 | 반전 (직진 / 실제) |
|---|---|---|---|
| 0 (이상 위치 없음) | 49° | **85°** | 3 / 21 |
| 1 | 26° | 49° | 6 / 18 |
| **3 (채택)** | **5°** | **19°** | 4 / 15 |
| 6 | 5° | 19° | 5 / 19 |
| 10 | 5° | 13° | 5 / 18 |

- 편차 = 일본 이동의 전체 방향이 한국 이동의 전체 방향에서 벗어난 각도.
- 가중치 0의 85°가 화면에서 본 "북동으로 가다 서북으로 꺾어 쭉 가는" 현상과 일치했다.
- 3 이상에서는 개선폭이 거의 같고 반전이 조금 늘어서 가장 작은 3을 골랐다. 실제 화면에서 더 다듬어야 할 수 있다.
- 편차 19°에도 45°를 넘는 곳이 30곳 중 8곳 남는다.

### 6.4 화면 확인 (에뮬레이터, 서울역→시청역 도보 흉내)

| 회차 | 확인한 것 |
|---|---|
| 1차 방식 | 오른쪽 지도가 일본에서 서울로 바뀜(앱 버그). 곧은 선과 회색 점선 발생 |
| 버그·반경 수정 후 | 일본에 머무름. 곧은 선은 순간이동 없이 시작하면 나오지 않음 |
| 2차 방식(도로 위 걷기), 이상 위치 추가 전 | 한국은 북동으로 가는데 일본은 비슷하게 가다 서북으로 꺾어 쭉 감 |
| 2차 방식, 가중치 3 | 일본 경로가 북쪽으로 올라가 한국 이동 방향과 비슷. 경로가 끊김 없이 이어짐. 곧은 선, 회색 점선 없음 |

> 화면 확인은 스크린샷 기준이며, 경로 전체가 아니라 카메라가 따라가는 끝부분을 본 것이다. 이번 경로에서 `deadEnd`가 발생했는지는 서버 로그에 남지 않아 모른다.

---

## 7. 구현 사항

### 7.1 서버

**Spring (`server/src/main/java/com/travelfootsteps/route/`, 2026-10-04 이관).** mock과 같은 JSON 계약으로 `POST /api/route/snap`, `/overseas-anchor/validate`, `/overseas-walk`를 제공한다.

| 파일 | 역할 |
|---|---|
| `RouteController` | 세 엔드포인트. 스냅 실패 시 받은 좌표를 그대로 반환 |
| `OverseasWalkService` | `walk_overseas_segment`와 도움 함수 포팅. 가중치 상수도 동일 |
| `OsrmClient` / `HttpOsrmClient` | OSRM `/nearest`, `/route`, `/match`. 호출당 5초 타임아웃, 실패는 예외 대신 빈 결과 |
| `GeoMath`, `GeoPoint`, `WalkState`, 요청·응답 DTO | 지리 계산, 좌표·상태 타입, 입력 검증 |

- **설정:** `application.yml`의 `osrm.base-urls.KR/JP`(환경변수 `OSRM_BASE_URL`, `OSRM_BASE_URL_JP`), `osrm.profile`(기본 `foot`). 주소가 비면 그 국가는 미지원으로 보고 `ok:false`를 돌려준다.
- **mock과 다른 점:** Google Roads 폴백 제거(한국은 항상 빈 응답이라), 좌표 범위·`points` 500개 상한 검증 추가(위반 시 400), Firebase 토큰 인증 필요(`/api/**`).
- **테스트:** `HttpOsrmClientTest`(응답 해석, 실패 정책), `OverseasWalkServiceTest`(가짜 도로망으로 불변식·`blocked`·`deadEnd`), `RouteControllerTest`(JSON 계약, 401, 400). 실행 중인 일본 OSRM으로 도쿄역 근처에서 60m씩 6번 걷는 확인도 했다.
- **한계:** 순간이동 방어는 아직 없다. 요청 하나에 OSRM `/route`가 최대 8번 순차로 나간다.

**mock (`mock-server/mock_server.py`).** 아래는 이관 전 원본 구현의 변경 내역이다.

- **추가:** `walk_overseas_segment`와 도움 함수, `POST /api/route/overseas-walk`.
- **변경:** 앵커 검증 응답에 도로에 붙인 좌표 `snapped` 추가(`snap_overseas_anchor`). 기존 `validate_overseas_anchor`는 이 함수를 감싸서 그대로 `bool`을 돌려준다.
- **유지:** 1차의 `project_points_from_anchor`, `match_overseas_segment`, `snap_overseas_segment`, `POST /api/route/overseas-snap`. 앱은 더 이상 부르지 않는다.
- **실행 조건:** `mock-server/.env`에 `OSRM_BASE_URL=http://localhost:5001`, `OSRM_BASE_URL_JP=http://localhost:5002`.

### 7.2 API

**`POST /api/route/overseas-anchor/validate`**

```json
// 요청
{ "country": "JP", "lat": 35.6812, "lng": 139.7671 }
// 응답 (통과: 도로 50m 이내)
{ "ok": true, "snapped": { "lat": 35.681198, "lng": 139.767109 } }
// 응답 (도로에서 멀거나 OSRM 실패)
{ "ok": false, "snapped": null }
```

**`POST /api/route/overseas-walk`**

```json
// 요청
{
  "country": "JP",
  "anchor": { "lat": 35.68, "lng": 139.76 },           // 도로 위 점
  "points": [ { "lat": 37.5547, "lng": 126.9723 }, ... ], // 한국 점들. 첫 점 = 직전 요청의 마지막 한국 점
  "state": null                                          // 첫 요청은 null, 이후는 직전 응답의 state
}
// 응답
{
  "ok": true,
  "offRoad": false,                                      // 항상 false (하위 호환용)
  "matched": [ { "lat": ..., "lng": ... }, ... ],        // 도로 위 경로. 첫 점 = anchor
  "newAnchor": { "lat": ..., "lng": ... },               // 마지막 점
  "event": null,                                         // "deadEnd" | "blocked" | null
  "state": { "heading": 32.1, "krHeading": 28.4, "trail": [...], "turnSide": 1, "ideal": {...} }
}
```

- `state`는 앱이 **내용을 해석하지 않고** 다음 요청에 그대로 되돌려 보낸다. 서버가 세션 상태를 들고 있지 않으므로 여러 사용자나 서버 재시작에 안전하다.
- `event`는 앱이 현재 쓰지 않는다. 화면에 표시하려면 응답 모델에 필드를 추가하면 된다.

### 7.3 앱

| 파일 | 변경 |
|---|---|
| `app/lib/features/footsteps/data/overseas_mapping_api.dart` | 새 파일. `validateOverseasAnchor`(도로에 붙인 좌표 `LatLng?` 반환), `walkOverseasSegment`, `OverseasWalkResult` |
| `app/lib/features/footsteps/map/overseas_anchor_picker_dialog.dart` | 새 파일. 지도 탭 → [동작] → 서버 검증 → 도로에 붙인 좌표 반환 |
| `app/lib/features/footsteps/map/overseas_mapping_test_page.dart` | 새 파일. 좌/우 분할 지도, 50m 트리거, `state` 전달, 위치점·방향 화살표 마커 |
| `app/lib/features/footsteps/footsteps_page.dart` | [해외 매핑 테스트] 버튼 추가(발걸음 탭) |
| `app/lib/features/footsteps/map/base_google_map.dart` | `onTap`, `myLocationEnabled` 파라미터 추가 |
| `app/lib/core/maps/configure_google_maps.dart` | 새 파일. Android에서 지도를 2개 동시에 띄우기 위한 렌더링 설정(`useAndroidViewSurface`) |
| `app/lib/main.dart`, `main_dev.dart` | 위 설정을 `runApp` 전에 호출 |
| `app/pubspec.yaml`, `pubspec.lock` | `google_maps_flutter_android`, `google_maps_flutter_platform_interface`를 직접 의존성으로 승격 |

**위치점과 방향 화살표.** 오른쪽 지도의 기본 파란 점은 실제 GPS(한국) 좌표라서 끄고(`myLocationEnabled: false`), 대신 일본 anchor 위치에 커스텀 마커를 둔다. 파란 점 위로 뻗은 삼각형 화살표를 `Canvas`로 그려 아이콘으로 만들고, 방향은 응답 경로 끝의 서로 다른 두 점으로 계산한 방위각을 `Marker.rotation`에 넣는다(`flat: true`).

**두 지도 동시 렌더링.** Android 기본 렌더링(Virtual Display)에서는 GoogleMap 위젯을 2개 띄우면 나중 지도의 타일이 비어 보였다. `useAndroidViewSurface`를 켜서 하이브리드 컴포지션으로 바꾸어 완화했다. 에뮬레이터에서는 여전히 타일이 안 보이는 경우가 있을 수 있다(`HowToTest.md` 참고).

### 7.4 인프라 (`osrm/`)

- `setup-japan.sh`: 간토 OSM 데이터 다운로드 후 `osrm-extract`(foot 프로필) → `partition` → `customize`.
- `docker-compose.yml`: `osrm-japan` 서비스(포트 5002) 추가. `osrm/README.md`에 일본 서버 절 추가.
- 개발 중에는 Docker 없이 Homebrew `osrm-routed`로 한국 `:5001`, 일본 `:5002`를 띄워 썼다.

---

## 8. 한계와 남은 과제

**알려진 한계**
- **`deadEnd`가 잦다.** 실제 굽은 한국 경로 30곳 중 12번(가중치 3 기준) 발생했다. 이상 위치 쪽으로 가려다 막다른 길에 들어가는 경우가 있는 것으로 보이며, 원인은 확인하지 않았다.
- **조회 수 증가.** 요청 하나에 OSRM `/route`가 최대 8번 나간다. 로컬 데모에서는 문제없지만 실서비스에는 부담이다.
- **가중치는 시뮬레이션으로 정한 값**이다(각도 1.0, 전진 2.0, 되돌아감 1.5, 이상 위치 3.0). 실제 화면과 다양한 경로로 더 다듬어야 할 수 있다.
- **한국 이동은 직진 또는 한 가지 경로**로만 시험했다. 한국에서 좌우로 자주 꺾는 경우는 충분히 시험하지 못했다.
- **완전한 방향 일치는 아니다.** 실제 경로 편차 중앙값 19°, 45° 초과 8/30곳. 일본 도로가 그 방향으로 이어지지 않는 곳에서는 벗어난다.
- **일본 이동의 컴퍼스 방향은 한국과 다를 수 있다.** 방향을 절대 방위가 아니라 회전량(상대)으로 다루는 설계이기 때문이다(다만 이상 위치가 한국 방향으로 끌어당긴다).
- **경계 부근 반전 일부와 그 외 반전의 원인은 확인하지 못했다.**
- **위치점 갱신은 50m 단위**다. 요청 사이에는 이전 위치에 머문다.

**남은 과제**
- **순간이동 방어:** 한국 GPS가 비현실적인 속도로 점프하면(예: 순간 수백 m) 그 점을 걸음으로 세지 않기. 2차 방식에서 순간이동 시 어떻게 동작하는지는 아직 검증하지 못했다.
- **`event` 활용:** `deadEnd`/`blocked`를 화면에 표시하거나 로그로 남기기.
- ~~**서버 이관**~~ → 2026-10-04 완료(§7.1). 남은 것: Spring 서버를 실제로 띄워 에뮬레이터 앱과 연결해 보기(Postgres 필요), 팀 저장소의 R1 서버와의 통합 조율, OSRM 프로덕션 배포.
- **시뮬레이션 스크립트 정리:** 지금은 저장소 밖에 있다. 회귀 검증용으로 정리해 둘 가치가 있다.

---

## 9. 재현 방법

1. **OSRM 두 서버**(한국 5001, 일본 5002) 실행. 절차는 `osrm/README.md`, `HowToTest.md` 1-1.
2. **서버**: `python3 mock-server/mock_server.py` (포트 8080). Spring 서버(`cd server && ./gradlew bootRun`, DB·Firebase 설정 필요)를 쓸 때는 `server/.env`에 `OSRM_BASE_URL`, `OSRM_BASE_URL_JP`를 넣는다.
3. **에뮬레이터 + 앱**: `flutter run -t lib/main_dev.dart` (`HowToTest.md` 2~3).
4. **해외 매핑 테스트**: 발걸음 탭 → [해외 매핑 테스트] → 도쿄 도로 위 지점 선택 → [동작].
5. **GPS 흘려보내기**: 에뮬레이터 위치를 걷기 시작 좌표로 **먼저** 맞춘 뒤, 한국 도보 경로를 10m 간격으로 쪼개 `adb emu geo fix <lng> <lat>`로 1~2초 간격 재생([4.3](#43-테스트-절차에서-알게-된-것-gps-순간이동)).

---

## 부록 A. 서버 핵심 코드

`mock-server/mock_server.py`의 2차 구현 핵심이다. 같은 로직이 `OverseasWalkService.java`에 옮겨져 있다. 하버사인(`_haversine_distance`), 방위각(`_bearing`), 목적지 계산(`_destination`)은 4.1의 수식 그대로이고, 나머지 도움 함수는 아래 요약을 따른다.

**도움 함수 요약**

| 함수 | 하는 일 |
|---|---|
| `_truncate_polyline(pts, d)` | 경로를 앞에서 `d`미터까지 자르고, 끝점은 마지막 선분 위를 보간 |
| `_resample(pts, step)` | 경로를 `step`미터 간격의 점으로 다시 뽑음 |
| `_overlap_fraction(path, trail)` | 경로(시작 10m 제외)가 지나온 길(`trail`)과 6m 이내로 겹치는 비율 |
| `_end_heading(path, span)` | 경로 끝 15m 구간의 진행 방향. 3m 미만이면 `None` |
| `_trim_trailing_spur(path, d)` | 끝이 교차로에서 60° 이상 꺾인 뒤 15m 미만이면 그 조각을 잘라냄(잘라낸 뒤 `d`의 절반 미만이면 자르지 않음) |
| `_osrm_route_points(base_url, origin, target)` | OSRM `/route`를 호출해 경로 좌표 목록을 돌려줌 |

**상수**

```python
WALK_OFFSETS = (0, 45, -45, 90, -90, 135, -135, 180)  # 원하는 방향 기준 후보 각도
WALK_W_ANGLE = 1.0    # 원하는 방향과 실제 진행 방향의 차이(0~1로 정규화)
WALK_W_SHORT = 2.0    # d보다 적게 전진한 비율
WALK_W_BACK = 1.5     # 최근 지나온 길과 겹친 비율
WALK_W_SIDE = 0.05    # 동점일 때 직전에 꺾은 쪽을 우선하는 가중
WALK_W_IDEAL = 3.0    # 이상 위치까지 거리(0~1.5로 제한) 가중
WALK_IDEAL_SCALE_M = 200.0
WALK_TURN_DEADBAND_DEG = 10       # 이보다 작은 한국 회전량은 GPS 흔들림으로 보고 무시
WALK_FORWARD_MAX_ANGLE = 100      # 이 각도 이내면 "앞으로 가는" 후보
WALK_FORWARD_MIN_ADVANCE = 0.5    # 앞으로 가는 후보가 d의 이 비율 이상 전진해야 함
WALK_BACK_RADIUS_M = 6
WALK_SPUR_MAX_M = 15
WALK_SPUR_TURN_DEG = 60
WALK_TRAIL_POINTS = 40            # 5m 간격으로 약 200m
```

**`walk_overseas_segment`**

```python
def walk_overseas_segment(country, anchor, kr_points, state):
    """anchor(도로 위 점)에서 한국 이동 거리만큼 일본 도로를 따라 걷는다.
    state는 앱이 그대로 들고 다니는 값: heading(일본 마지막 진행 방향), krHeading(직전
    요청의 한국 진행 방향), trail(최근 지나온 점), turnSide(직전에 꺾은 쪽 +1/-1)."""
    base_url = COUNTRY_OSRM_URLS.get(country, "")
    if not base_url or not anchor or len(kr_points) < 2:
        return {"ok": False}

    d = _polyline_length(kr_points)
    if d == 0:
        return {"ok": False}

    state = state or {}
    kr_heading = math.degrees(_bearing(kr_points[0], kr_points[-1]))
    heading = state.get("heading")
    prev_kr = state.get("krHeading")
    if heading is None:
        desired = kr_heading
    else:
        delta = _wrap180(kr_heading - prev_kr) if prev_kr is not None else 0.0
        if abs(delta) < WALK_TURN_DEADBAND_DEG:
            delta = 0.0
        desired = (heading + delta) % 360

    trail = state.get("trail") or []
    turn_side = state.get("turnSide") or 1
    ideal = _destination(state.get("ideal") or anchor, math.radians(kr_heading), d)

    candidates = []
    for offset in WALK_OFFSETS:
        target = _destination(anchor, math.radians(desired + offset), d)
        route = _osrm_route_points(base_url, anchor, target)
        if not route:
            continue
        path, advance = _truncate_polyline(route, d)
        if _haversine_distance(path[0], anchor) < 15:
            path = [anchor] + path[1:]
        else:
            path = [anchor] + path
        chord = math.degrees(_bearing(path[0], path[-1])) if advance >= 5 else None
        candidates.append({
            "offset": offset,
            "path": path,
            "advance": advance,
            "angle": 180.0 if chord is None else _angle_diff(chord, desired),
            "overlap": _overlap_fraction(path, trail),
            "ideal_err": _haversine_distance(path[-1], ideal),
        })

    next_state = {"heading": heading, "krHeading": kr_heading, "trail": trail,
                  "turnSide": turn_side, "ideal": ideal}
    if not candidates:
        return {"ok": True, "offRoad": False, "matched": [anchor], "newAnchor": anchor,
                "event": "blocked", "state": next_state}

    forward = [
        c for c in candidates
        if c["angle"] <= WALK_FORWARD_MAX_ANGLE
        and c["advance"] >= WALK_FORWARD_MIN_ADVANCE * d
        and c["overlap"] < 0.5
    ]

    event = None
    if forward:
        def score(c):
            side_bonus = WALK_W_SIDE if c["offset"] * turn_side > 0 else 0.0
            return (WALK_W_ANGLE * c["angle"] / 180
                    + WALK_W_SHORT * max(0.0, 1 - c["advance"] / d)
                    + WALK_W_BACK * c["overlap"]
                    + WALK_W_IDEAL * min(c["ideal_err"] / WALK_IDEAL_SCALE_M, 1.5)
                    - side_bonus)
        chosen = min(forward, key=score)
    else:
        # 앞으로 갈 길이 없다(막다른 길): 되돌아가는 쪽 중 가장 멀리 가는 후보를 택한다.
        event = "deadEnd"
        backward = [c for c in candidates if c["angle"] > WALK_FORWARD_MAX_ANGLE] or candidates
        chosen = max(backward, key=lambda c: c["advance"])

    path = _trim_trailing_spur(chosen["path"], d)
    new_heading = _end_heading(path)
    if chosen["offset"] != 0:
        turn_side = 1 if chosen["offset"] > 0 else -1

    trail_points = [] if event == "deadEnd" else trail
    next_state = {
        "heading": new_heading if new_heading is not None else heading,
        "krHeading": kr_heading,
        "trail": (trail_points + _resample(path, 5.0))[-WALK_TRAIL_POINTS:],
        "turnSide": turn_side,
        "ideal": ideal,
    }
    return {"ok": True, "offRoad": False, "matched": path, "newAnchor": path[-1],
            "event": event, "state": next_state}
```
