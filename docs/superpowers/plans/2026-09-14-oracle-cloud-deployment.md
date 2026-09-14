# Oracle Cloud 서버 배포 Implementation Plan

> **For agentic workers:** Task 1은 REQUIRED SUB-SKILL: superpowers:subagent-driven-development (recommended) 또는 superpowers:executing-plans로 진행한다. **Task 1 이후의 "배포 런북"은 코드 작업이 아니라 Oracle 콘솔·SSH를 통한 수동 진행 단계다 — 서브에이전트에 디스패치하지 말고, 사용자와 함께 대화 세션에서 하나씩 실행한다.**

**Goal:** 로컬에서만 돌던 Spring Boot 서버를 Oracle Cloud Always Free VM에 상시 배포해, 팀원들의 앱이 실제 호출할 수 있는 URL을 확보한다.

**Architecture:** VM.Standard.A1.Flex(ARM, 2 OCPU/12GB) 위에 Java 21 + PostgreSQL 16 + Nginx(80→8080 리버스 프록시) + systemd. HTTPS는 지금 안 하고(도메인 없음), IP+HTTP로 직접 연다.

**Tech Stack:** Oracle Cloud Infrastructure(OCI), Ubuntu 24.04, Nginx, systemd, Java 21(Temurin), PostgreSQL 16

## Global Constraints

- 8080(앱 직접), 5432(Postgres)는 절대 외부에 노출하지 않는다 — Nginx(80)만 외부 접점.
- `.env`/`firebase-service-account.json`은 절대 git에 올리지 않는다(이미 `.gitignore` 대상) — VM에는 `scp`로 직접 전달한다.
- Postgres 비밀번호는 로컬 개발 기본값(`postgres`)을 그대로 쓰지 않는다 — 배포 시 새로 생성한다.
- 이번 스코프는 수동 배포까지다. CI/CD 자동 배포, 도메인/HTTPS는 스코프 밖(설계 문서 "스코프 밖" 절 참고).

---

### Task 1: 배포 설정 파일 작성 (저장소에 커밋)

**Files:**
- Create: `deploy/nginx.conf`
- Create: `deploy/travel-footsteps-server.service`
- Create: `deploy/deploy.sh`
- Create: `docs/deployment.md`

**Interfaces:**
- Consumes: `server/build/libs/server-0.0.1-SNAPSHOT.jar`(기존 `./gradlew bootJar` 산출물, 경로 확정돼 있음), `server/.env`(기존 파일, `spring.config.import: optional:file:.env[.properties]`로 Spring Boot가 자동으로 읽음 — 별도 systemd 환경변수 전달 불필요)
- Produces: 이 Task가 만드는 4개 파일은 이후 "배포 런북" 단계에서 VM에 그대로 배치된다. 파일 이름·경로는 런북에서 정확히 이 이름으로 참조하므로 바꾸지 않는다.

- [ ] **Step 1: Nginx 리버스 프록시 설정 작성**

`deploy/nginx.conf`:

```nginx
# Oracle Cloud VM에 배치될 Nginx 설정. 80번 포트로 들어온 요청을 Spring Boot(8080)로 넘긴다.
# WebSocket(STOMP, /ws)은 프로토콜 업그레이드 헤더를 별도로 전달해야 연결이 유지된다.
server {
    listen 80;
    server_name _;

    location /ws {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

- [ ] **Step 2: systemd 서비스 유닛 작성**

`deploy/travel-footsteps-server.service`:

```ini
# /etc/systemd/system/travel-footsteps-server.service로 배치한다.
# WorkingDirectory를 server/로 잡아두면, Spring Boot의 spring.config.import가
# 같은 디렉터리의 .env를 자동으로 읽는다(로컬 개발 때와 동일한 메커니즘) —
# 이 유닛 파일 자체에는 비밀값을 하나도 적지 않는다.
[Unit]
Description=Travel Footsteps Spring Boot Server
After=network.target postgresql.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/travel-footsteps/server
ExecStart=/usr/bin/java -jar /home/ubuntu/travel-footsteps/server/build/libs/server-0.0.1-SNAPSHOT.jar
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: 배포 스크립트 작성**

`deploy/deploy.sh`:

```bash
#!/bin/bash
# VM 위에서 직접 실행한다: bash deploy/deploy.sh
# 최신 코드를 받아 다시 빌드하고 서비스를 재시작한다.
set -euo pipefail

cd /home/ubuntu/travel-footsteps
git pull

cd server
./gradlew bootJar

sudo systemctl restart travel-footsteps-server
sleep 3
sudo systemctl status travel-footsteps-server --no-pager
```

- [ ] **Step 4: 실행 권한 표시 + 배포 런북 문서 작성**

```bash
chmod +x deploy/deploy.sh
```

`docs/deployment.md`:

```markdown
# 배포 런북

VM 최초 세팅과 이후 재배포 절차. 상세 단계는
`docs/superpowers/plans/2026-09-14-oracle-cloud-deployment.md`의 "배포 런북" 섹션 참고.

## 재배포 (코드 갱신)

VM에 SSH 접속 후:

\`\`\`bash
bash /home/ubuntu/travel-footsteps/deploy/deploy.sh
\`\`\`

## 로그 확인

\`\`\`bash
sudo journalctl -u travel-footsteps-server -f
\`\`\`

## 서비스 상태 확인

\`\`\`bash
sudo systemctl status travel-footsteps-server
\`\`\`
```

- [ ] **Step 5: 파일 검증**

```bash
cd deploy && nginx -t -c "$(pwd)/nginx.conf" 2>&1 || echo "로컬에 nginx 없으면 이 검증은 VM에서 실제로 배치할 때 진행 — 문법 오류만 있는지 눈으로 재확인"
```

로컬에 nginx가 없으면 문법을 직접 재검토한다(중괄호 짝, 세미콜론 누락 여부). 실제 유효성 검증은 이후 "배포 런북" Step E에서 VM에 배치한 뒤 `nginx -t`로 확정한다.

- [ ] **Step 6: 커밋**

```bash
git add deploy/nginx.conf deploy/travel-footsteps-server.service deploy/deploy.sh docs/deployment.md
git commit -m "chore(deploy): Oracle Cloud 배포용 nginx/systemd/deploy 스크립트 추가"
```

---

## 배포 런북 (수동 진행 — Claude와 함께 대화 세션에서 하나씩)

**Task 1 완료 후 진행.** 아래는 서브에이전트 디스패치 대상이 아니다 — 사용자가 Oracle 콘솔에서 직접 클릭하거나 SSH 터미널에 명령을 입력하고, Claude는 각 단계에서 정확한 값과 다음 행동을 안내한다.

### Step A: Oracle Cloud 계정 + VM 인스턴스 생성

1. https://cloud.oracle.com 가입(신용카드 등록 필요하나 Always Free 리소스는 과금 안 됨).
2. Compute → Instances → "Create Instance".
3. **Image**: Canonical Ubuntu 24.04 (aarch64).
4. **Shape**: `VM.Standard.A1.Flex` 선택 → OCPU 2, Memory 12GB로 조정(Always Free 한도 4 OCPU/24GB 이내).
5. **Networking**: 기본 VCN 사용, "Assign a public IPv4 address" 체크.
6. **SSH keys**: "Generate a key pair for me" 선택 → 개인 키(.pem 파일) 다운로드해서 안전한 곳에 보관(이게 없으면 SSH 접속 자체가 불가능).
7. "Create" → 생성 완료 후 **Public IP 주소**를 메모해 둔다(이후 모든 단계에서 필요).

### Step B: 네트워크 보안 설정 (Security List + OS 방화벽 둘 다)

Oracle Cloud는 두 겹의 방화벽이 있다 — 하나만 열면 여전히 막힌다.

1. **Security List**: 해당 VM의 VCN → Security Lists → 기본 목록 → "Add Ingress Rules": Source CIDR `0.0.0.0/0`, IP Protocol TCP, Destination Port `80` 추가. (22는 보통 기본 목록에 이미 열려 있음 — 없으면 같이 추가.)
2. **OS 방화벽(iptables)**: Ubuntu 이미지가 자체 iptables 규칙으로 인입 트래픽을 추가로 막아두는 경우가 있다 — Security List만 열고 이 단계를 건너뛰면 "포트는 열었는데 접속이 안 되는" 상황이 난다. SSH 접속 후:
   ```bash
   sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
   sudo netfilter-persistent save
   ```

### Step C: SSH 접속 + 소프트웨어 스택 설치

```bash
ssh -i <다운로드한_키.pem> ubuntu@<Public_IP>
```

접속 후:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y openjdk-21-jdk postgresql postgresql-contrib nginx git
```

PostgreSQL DB/사용자 생성(로컬 개발 기본값 `postgres/postgres`를 그대로 쓰지 않는다):

```bash
sudo -u postgres psql -c "CREATE DATABASE travelfootsteps;"
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '<새로운_강력한_비밀번호>';"
```

### Step D: 저장소 clone + 비밀정보 전달

VM에서:

```bash
git clone https://github.com/Cho-Youngjin/2026CapstoneDesign.git travel-footsteps
```

로컬 PC(사용자 자신의 컴퓨터)에서, VM으로 비밀 파일 2개를 전송:

```bash
scp -i <다운로드한_키.pem> server/.env ubuntu@<Public_IP>:/home/ubuntu/travel-footsteps/server/.env
scp -i <다운로드한_키.pem> server/src/main/resources/firebase-service-account.json ubuntu@<Public_IP>:/home/ubuntu/travel-footsteps/server/src/main/resources/firebase-service-account.json
```

`server/.env`의 `DB_URL`/`DB_USERNAME`/`DB_PASSWORD`를 Step C에서 만든 값으로 맞춰 VM에서 수정:

```bash
# VM에서
nano /home/ubuntu/travel-footsteps/server/.env
# DB_PASSWORD=<Step C에서 만든 비밀번호> 로 맞춘다
```

### Step E: 빌드 + 서비스 등록 + 시작

VM에서:

```bash
cd /home/ubuntu/travel-footsteps/server
./gradlew bootJar

sudo cp /home/ubuntu/travel-footsteps/deploy/travel-footsteps-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now travel-footsteps-server

sudo nginx -t -c /home/ubuntu/travel-footsteps/deploy/nginx.conf
sudo cp /home/ubuntu/travel-footsteps/deploy/nginx.conf /etc/nginx/sites-available/default
sudo systemctl restart nginx
```

### Step F: 검증

로컬 PC 브라우저(또는 curl)에서:

```bash
curl http://<Public_IP>/api/health
```

기대: `{"status":"UP"}`.

다음으로, 실제 Firebase ID 토큰으로 인증이 필요한 엔드포인트까지 확인한다(예: `GET /api/countries`) — 이건 이 프로젝트가 처음으로 "진짜 새 환경"에서 Firebase Admin SDK + Flyway 마이그레이션이 정상 작동하는지 검증하는 순간이므로, CI 때처럼 예상 못 한 문제(예: `firebase-service-account.json` 경로 오류, Flyway 마이그레이션 순서 문제)가 나올 수 있다. 문제가 나오면 `sudo journalctl -u travel-footsteps-server -f`로 로그를 보면서 같이 진단한다.

### Step G: 팀원에게 전달

Public IP를 Flutter 담당 팀원에게 전달한다. 그 팀원이 할 일(이 계획의 스코프 밖, 참고용):
- `network_security_config.xml`에 이 IP만 예외로 cleartext 허용 추가
- 앱의 서버 base URL을 이 IP로 설정(Phase 0 문서의 "배포 시에는 서버 도메인으로 교체한다" 부분)

---

## Self-Review

**스펙 커버리지**: 설계 문서의 "2. 서버 배포" 섹션 항목(인스턴스 스펙, 소프트웨어 스택, 프로세스 관리, 네트워크 보안, HTTPS 보류, 비밀정보 전달, 배포 프로세스, 앱 연동 안내, 검증 계획)이 Task 1(설정 파일) + 배포 런북 Step A~G에 전부 반영됨. CI/CD·도메인/HTTPS는 설계 문서에서도 명시적으로 스코프 밖이라 이 계획에도 없음.
