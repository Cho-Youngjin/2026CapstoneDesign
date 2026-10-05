# OSRM 도로 스냅 서버 (R3 발걸음 실시간 경로용)

발걸음 탭의 실시간 이동 경로(RoutePoints)를 실제 도로 위로 스냅해서 보여주기
위한 서버. `mock-server/mock_server.py`와 Spring 서버(`server/.../route/`)의 `/api/route/snap`이 이 서버를 호출한다.

## 왜 OSRM인가

처음엔 Google Roads API를 붙였다. 인증·활성화까지는 정상이었지만, 실제로
호출해보니 서울시청·부산·강남·제주 등 한국 좌표는 전부 빈 응답만 왔다 — 설정
문제가 아니라 **Google이 한국 도로 데이터를 이 API용으로 아예 갖고 있지 않기
때문**으로 보인다(국내 공간정보 반출 규제로 정밀 도로망을 해외로 못 내보내는
것과 같은 맥락 — Google Maps 내비게이션이 한국에서 온전히 안 되는 이유이기도
하다). 뉴욕 좌표로는 정상 동작했다.

한국이 주 무대인 앱이라 실제 도로 데이터를 가진 **OSRM(OpenStreetMap 기반)**
으로 바꿨다. 자체 호스팅이 필요하지만, 한국 도로망이 실제로 존재하고
무료다.

## 실행 방법

사전 조건: Docker (Desktop 또는 CLI) 설치.

```bash
./setup.sh          # 최초 1회 — 한국 OSM 데이터 다운로드 + 전처리 (몇 분 소요)
docker compose up -d   # 서버 시작 (http://localhost:5001)
```

종료: `docker compose down`

## mock 서버와 연결하기

`mock-server/.env`에 한 줄 추가:

```
OSRM_BASE_URL=http://localhost:5001
```

`mock_server.py`는 이 값이 있으면 OSRM을 우선 쓰고, 없거나 호출이 실패하면
Google Roads API로(그것도 없으면 원본 좌표 그대로) 자동 폴백한다 — 코드
수정 없이 켜고 끌 수 있다.

## 해외 발걸음(일본) 서버

"국내 이동을 해외 도로망에 투영해 보여주는" 해외 발걸음 기능의 데모 대상국은
일본으로 확정했다(설계는
`docs/superpowers/specs/2026-09-29-overseas-footsteps-route-projection.md`
참고). 별도 OSRM 인스턴스로 띄운다 — 일본 전체 extract는 한국보다 훨씬 커서
데모에 필요한 간토 지역(도쿄 등)만 받는다.

```bash
./setup-japan.sh     # 최초 1회 — 간토 OSM 데이터 다운로드 + 전처리
docker compose up -d  # osrm-japan 서비스가 함께 뜬다 (http://localhost:5002)
```

`mock-server/.env`에 추가로 한 줄:

```
OSRM_BASE_URL_JP=http://localhost:5002
```

`mock_server.py`의 `/api/route/overseas-anchor/validate`, `/api/route/overseas-snap`
엔드포인트가 국가 코드(`KR`/`JP`)에 따라 `OSRM_BASE_URL`/`OSRM_BASE_URL_JP`
중 알맞은 인스턴스를 호출한다.

## 검증 방법 (직접 호출)

```bash
curl "http://localhost:5001/route/v1/foot/127.329145,37.545996;127.3098,37.5548?overview=full&geometries=geojson"
```

`code: "Ok"`와 함께 실제 도보 경로 좌표가 나오면 정상이다. (좌표 순서가
`lng,lat`인 것에 주의 — GeoJSON 관례라 Google과 반대다.)

## 실서버(Spring)에 연결할 때

`server/`의 `route` 패키지(2026-10-04 이관)가 이 컨테이너를 그대로 호출한다. `server/.env`에
`OSRM_BASE_URL`(한국, 5001)과 `OSRM_BASE_URL_JP`(일본, 5002)를 넣으면 된다(`application.yml`의
`osrm.base-urls`). Spring 쪽에는 Google Roads 폴백이 없고, 스냅에 실패하면 받은 좌표를 그대로 돌려준다.

## 데이터 갱신

한국 도로 데이터가 오래됐다 싶으면 `data/` 디렉터리를 지우고 `./setup.sh`를
다시 실행하면 최신 OSM 추출본을 새로 받아 전처리한다.
