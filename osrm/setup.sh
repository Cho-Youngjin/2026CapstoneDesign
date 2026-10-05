#!/usr/bin/env bash
# 한국 도로 데이터를 받아 OSRM(도보 프로필)용으로 전처리한다. 한 번만 실행하면
# 되고(도로 데이터가 자주 바뀌지 않는 한), 이후엔 docker-compose.yml로 그냥
# 서버만 띄우면 된다. Docker만 있으면 되고, osrm-backend를 로컬에 따로
# 설치할 필요는 없다 — 전처리도 osrm/osrm-backend 이미지로 실행한다.
#
# 실행: ./setup.sh
# 소요 시간: 데이터 다운로드(약 280MB) + 전처리 몇 분 정도(맥북 기준 실측 2~3분)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
PBF_FILE="south-korea.osm.pbf"
OSRM_BASE="south-korea.osrm"

# Geofabrik의 "-latest" 별칭은 실제 파일명(날짜 포함)으로 리다이렉트된다.
PBF_URL="https://download.geofabrik.de/asia/south-korea-latest.osm.pbf"

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

if [ ! -f "$PBF_FILE" ]; then
  echo "==> 한국 OSM 데이터 다운로드 중..."
  curl -L -o "$PBF_FILE" "$PBF_URL"
else
  echo "==> $PBF_FILE 이미 있음, 다운로드 생략"
fi

if [ -f "$OSRM_BASE" ]; then
  echo "==> 이미 전처리된 $OSRM_BASE 가 있음. 다시 만들려면 data/ 디렉터리를 지우고 재실행하세요."
  exit 0
fi

# osrm/osrm-backend 공식 이미지는 /opt/foot.lua 등 프로필을 기본 내장한다.
echo "==> osrm-extract (도보 프로필)"
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-extract -p /opt/foot.lua "/data/$PBF_FILE"

echo "==> osrm-partition"
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-partition "/data/$OSRM_BASE"

echo "==> osrm-customize"
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-customize "/data/$OSRM_BASE"

echo "==> 완료. 'docker compose up -d'로 서버를 띄우세요 (http://localhost:5001)."
