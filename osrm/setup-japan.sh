#!/usr/bin/env bash
# 일본(간토 지역) 도로 데이터를 받아 OSRM(도보 프로필)용으로 전처리한다.
# "해외 발걸음" 데모 대상국이 일본으로 확정됨에 따라 setup.sh(한국)와 같은
# 패턴으로 추가한 스크립트 — 자세한 배경은
# docs/superpowers/specs/2026-09-29-overseas-footsteps-route-projection.md 참고.
#
# 일본 전체 extract는 한국보다 훨씬 커서, 데모에 필요한 간토 지역(도쿄 등)만
# 받는다. 실행: ./setup-japan.sh
# 소요 시간: 데이터 다운로드 + 전처리 몇 분 정도 (간토 extract 기준)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data-japan"
PBF_FILE="kanto.osm.pbf"
OSRM_BASE="kanto.osrm"

# Geofabrik의 "-latest" 별칭은 실제 파일명(날짜 포함)으로 리다이렉트된다.
PBF_URL="https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

if [ ! -f "$PBF_FILE" ]; then
  echo "==> 간토 OSM 데이터 다운로드 중..."
  curl -L -o "$PBF_FILE" "$PBF_URL"
else
  echo "==> $PBF_FILE 이미 있음, 다운로드 생략"
fi

if [ -f "$OSRM_BASE" ]; then
  echo "==> 이미 전처리된 $OSRM_BASE 가 있음. 다시 만들려면 data-japan/ 디렉터리를 지우고 재실행하세요."
  exit 0
fi

echo "==> osrm-extract (도보 프로필)"
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-extract -p /opt/foot.lua "/data/$PBF_FILE"

echo "==> osrm-partition"
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-partition "/data/$OSRM_BASE"

echo "==> osrm-customize"
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-customize "/data/$OSRM_BASE"

echo "==> 완료. 'docker compose up -d'로 서버를 띄우세요 (http://localhost:5002)."
