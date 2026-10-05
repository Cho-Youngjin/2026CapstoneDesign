아래 명령은 Android Studio에서 Capstone_2026 프로젝트를 열었을 때 뜨는 터미널(프로젝트 루트, `/Users/parkjunhyeok/Developer/Capstone_2026`) 기준 상대 경로다. 새 터미널 탭을 열면 항상 이 루트에서 시작한다.

1) mock 서버 실행 (터미널 1)

python3 mock-server/mock_server.py

포트 8080에서 뜨고, 콘솔에 요청 로그가 찍힙니다 (Ctrl+C로 종료).

(R1 서버 없이 R3만 검증하는 용도다. 같은 해외 매핑 엔드포인트가 Spring 서버 `server/`에도 구현돼 있다 — 그쪽을 쓰려면 `server/.env`에 아래 `OSRM_BASE_URL`, `OSRM_BASE_URL_JP`를 넣고 `cd server && ./gradlew bootRun`. DB(Postgres)와 Firebase 설정이 필요하고 `/api/**`는 로그인 토큰을 요구한다.)

`mock-server/.env`에 아래 값을 넣어두면 도로 스냅/해외 매핑이 실제 OSRM 서버를 쓴다(없으면 목 데이터·원본 좌표로 조용히 폴백):

GOOGLE_SERVER_API_KEY=...
OSRM_BASE_URL=http://localhost:5001       # 한국 도로 스냅
OSRM_BASE_URL_JP=http://localhost:5002    # 해외 매핑 테스트(일본)용

1-1) OSRM 서버 실행 (선택, 터미널 1-1 / 1-2 — 도로 스냅·해외 매핑 테스트를 검증하려면 필요)

한국(도보 프로필, 포트 5001):

cd osrm
./setup.sh          # 최초 1회 — 한국 OSM 데이터 다운로드 + 전처리
docker compose up -d osrm
cd ..

일본 간토 지역(도쿄 등, 포트 5002) — "해외 매핑 테스트" 전용:

cd osrm
./setup-japan.sh    # 최초 1회 — 간토 OSM 데이터 다운로드 + 전처리 (일본 전체보다 작지만 시간 좀 걸림)
docker compose up -d osrm-japan
cd ..

Docker가 없는 환경(예: 이 저장소를 검증한 맥)에서는 Homebrew로 설치한 `osrm-backend`(`osrm-extract`/`osrm-partition`/`osrm-customize`/`osrm-routed`)로 동일한 전처리를 직접 돌려도 된다 — `setup.sh`/`setup-japan.sh`의 각 단계를 `docker run osrm/osrm-backend ...` 대신 로컬 바이너리로 실행하면 된다. 자세한 배경은 `osrm/README.md` 참고.

2) Android 에뮬레이터 부팅 (터미널 2, 최초 1회만 있으면 이후 그대로 재사용 가능)

export ANDROID_HOME=/Users/parkjunhyeok/Library/Android/sdk
$ANDROID_HOME/emulator/emulator -avd medium_phone

($ANDROID_HOME/emulator/emulator -list-avds로 다른 AVD 확인 가능)

3) 앱 실행 (터미널 3, app/ 디렉토리에서)

cd app
flutter run -t lib/main_dev.dart

main_dev.dart는 Firebase 로그인 없이 DevAuthRepository로 자동 로그인되는 개발용 진입점입니다. 앱은 Android에서 http://10.0.2.2:8080으로 요청하므로 1)의 mock 서버를 자동으로 바라봅니다.

4) 해외 매핑 테스트 (국내 이동 → 해외 도로망 위 걸음, 구현 보고서: docs/superpowers/specs/2026-09-30-korea-overseas-mapping-report.md)

발걸음 탭의 빈 곳에 있는 **[해외 매핑 테스트]** 버튼을 누르면:

1. 팝업 지도에서 해외 출발 지점(anchor)을 탭으로 선택 → [동작] 클릭 시 그 자리에서 서버가 OSRM `/nearest`로 도로 근접 여부를 검증한다(도로가 없는 지점을 고르면 재선택 요구). 통과하면 탭한 지점이 아니라 **도로에 붙인 좌표**가 출발점이 된다.
2. 검증을 통과하면 화면이 좌(한국 실이동)/우(해외 경로)로 분할되고, 실제로 에뮬레이터 위치가 바뀔 때마다(4-1 참고) 누적 50m마다 서버(`/api/route/overseas-walk`)가 호출되어, 한국에서 걸은 거리만큼 일본 도로를 따라 걸은 경로가 오른쪽 지도에 이어진다. 오른쪽 지도의 파란 점+화살표가 현재 위치와 진행 방향이다. 앞이 막힌 길에서는 되돌아가며(서버 응답의 `deadEnd` 이벤트), 도로 밖 구간은 만들지 않는다.
3. **[멈춤]**을 누르면 세션이 끝난다 — 여기서 그린 경로는 체크인/RoutePoint로 저장되지 않는다.

4-1) 에뮬레이터에서 GPS 이동 흉내내기

에뮬레이터 확장 컨트롤(⋮ → Location)에서 좌표를 하나씩 바꾸거나, 아래처럼 adb로 짧은 간격을 두고 여러 좌표를 연속으로 흘려보내면 실제로 걷는 것처럼 `distanceFilter: 10` 위치 스트림이 반응한다(양수역→운길산역 같은 실제 도보 경로를 OSRM `/route`로 미리 뽑아 촘촘히 보간해서 재생하면 자연스럽다):

adb -s <device> emu geo fix <lng> <lat>

**테스트 시작 전에 에뮬레이터 위치를 걷기 시작 좌표로 먼저 맞춰 두세요.** 에뮬레이터는 시작할 때 이전 위치를 첫 GPS 값으로 내보낸 뒤 새 위치로 점프하는 것으로 보이는데, 앱은 이 점프를 걸음으로 세서 출발점에서 곧은 선이 생길 수 있습니다.

참고

adb/emulator 명령이 PATH에 없다면 export PATH=$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH를 먼저 실행하세요.
실행 중 r(hot reload), R(hot restart), q(종료) 키를 터미널에서 바로 사용할 수 있습니다.
에뮬레이터 기본 위치는 도쿄 근처라, 발걸음 체크인/주변정보는 그 좌표 기준으로 동작합니다. 에뮬레이터 확장 컨트롤(⋮ → Location)에서 위치를 바꿔 다른 국가로도 테스트할 수 있습니다.
**알려진 에뮬레이터 제약**: GoogleMap 위젯을 화면에 2개 동시에 띄우면(해외 매핑 테스트의 좌/우 분할 화면 등) `google_maps_flutter_android`의 `useAndroidViewSurface`(하이브리드 컴포지션)를 켜도, 두 번째 지도는 마커·폴리라인은 정상 렌더링되지만 기본 지도 타일(도로·배경 이미지)이 안 보이는 경우가 있습니다 — 실측 결과 에뮬레이터의 GPU 렌더링 컨텍스트 공유 제약으로 보이며, 실기기에서는 보통 정상 동작합니다. 로직(anchor 검증, 50m 트리거, 도로 위 걷기)은 이 상태에서도 서버 로그로 정상 동작이 확인됩니다.
