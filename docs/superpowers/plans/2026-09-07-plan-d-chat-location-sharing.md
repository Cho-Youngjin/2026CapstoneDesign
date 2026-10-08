# Plan D — 서버 + 앱: 그룹 채팅(그룹→DM→사진→읽음) + 위치공유 권한 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **2026-10-08 개정 — Firestore 기반에서 Spring 서버 기반으로 전면 재작성.**
> 초판(2026-09-07)은 채팅을 Firestore + Firebase Storage + Cloud Functions로 설계했다. 팀 결정으로 채팅을 **기존 Spring 서버에 직접 구현**하도록 바꿨고, 서버 구현까지 R2가 맡는다. 초판은 git 이력에 남아 있다.
> 바뀐 이유와 영향은 아래 "설계 결정 기록"에 정리했다.

**Goal:** 6자리 초대 코드로 여행 그룹을 만들고 참여할 수 있고, 그 그룹 안에서 그룹 채팅 → 1:1 DM → 사진 전송 → 읽음 표시 순으로 채팅이 단계적으로 동작한다. 그룹 멤버만 그 방의 메시지와 실시간 위치를 구독할 수 있다.

**Architecture:** 데이터는 전부 PostgreSQL(`chat_room`, `chat_room_member`, `chat_message`, `app_user`)에 둔다. **보내기는 REST, 받기는 STOMP**로 나눈다 — 앱은 `POST /api/rooms/{id}/messages`로 메시지를 보내고(저장 성공 여부와 메시지 id를 즉시 응답으로 받는다), 서버는 저장 직후 `/topic/rooms/{id}/messages`로 같은 메시지를 브로드캐스트한다. 이전 메시지는 REST 페이지 조회로 가져온다. STOMP 인프라는 Plan A Task 10이 만든 `WebSocketConfig`(`/ws`, 인메모리 `/topic` 브로커)와 `StompAuthChannelInterceptor`(CONNECT 시 Firebase 토큰 검증)를 그대로 재사용하고, **SUBSCRIBE 시 방 멤버인지 검사하는 인터셉터를 하나 추가**한다. 사진은 서버 로컬 디스크에 저장하고 멤버만 내려받을 수 있는 REST로 제공한다. 읽음 표시는 메시지마다 쓰지 않고 멤버 행의 `last_read_message_id` 하나만 갱신한다.

**Tech Stack:** 서버 — Spring Boot 3.5 / Java 21 / JPA / Flyway / Spring WebSocket(STOMP) / Firebase Admin(FCM, 선택) · 앱 — Flutter / Riverpod 3 / go_router / dio(`apiClientProvider`) / `stomp_dart_client` / `image_picker`(이미 있음)

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §3, §6-④, §7
**선행 계획서:** Phase 0(`AuthRepository`, `apiClientProvider`, `resolveBaseUrl`), Plan A Task 10(`WebSocketConfig`, `StompAuthChannelInterceptor`, `LocationRelayController`)

**담당:** R2(서버·앱 모두). 리뷰는 서버 구조와 STOMP 인증을 만든 R1이 맡는다. 위치공유 **앱 클라이언트**는 스펙 §8대로 R3 소관이다 — 이 계획서는 서버 쪽 권한 검사와, R3가 재사용할 STOMP 연결 계층까지만 만든다(Task 9).

---

## 설계 결정 기록

| 결정 | 선택 | 이유 |
|---|---|---|
| 채팅 저장소 | Firestore → **PostgreSQL** | 팀 결정. 서버 하나에 데이터를 모아 권한 검사·테스트를 기존 방식(Testcontainers + MockMvc)으로 통일한다. Firestore 보안 규칙·Cloud Functions라는 별도 기술 축이 사라진다. |
| 보내기 경로 | STOMP SEND 대신 **REST POST** | 응답으로 저장 성공 여부와 메시지 id를 확실히 받는다(STOMP SEND는 성공/실패를 알려주지 않는다). 입력 검증·권한 검사·테스트가 기존 컨트롤러 패턴 그대로다. 받는 쪽만 STOMP로 실시간이면 사용자 체감은 같다. |
| 읽음 기준 | `lastReadAt`(시각) 대신 **`last_read_message_id`** | 메시지 id는 서버가 매기는 단조 증가값이라 기기 시계 오차의 영향을 받지 않는다. "안 읽은 개수 = 내 마지막 읽은 id보다 큰, 남이 보낸 메시지 수"로 바로 센다. 쓰기 횟수를 줄인다는 스펙 §6-④의 의도(메시지마다 쓰지 않음)는 그대로 지킨다. |
| 사진 저장 | Firebase Storage 대신 **서버 로컬 디스크** | Firebase Storage는 요금제 정책상 신규 버킷에 Blaze(종량제) 요금제가 필요해 팀이 쓰는 무료 요금제로는 쓰기 어렵다. 배포 대상(Oracle Cloud VM)에 디스크가 있으므로 경로만 설정으로 뺀다. 멤버만 내려받도록 REST로 감싼다. |
| 사용자 이름·사진 | Firestore `users/{uid}` 대신 **`app_user` 테이블** | 서버의 `TokenVerifier`는 uid만 돌려준다. 채팅 화면에 이름을 띄우려면 서버가 프로필을 알아야 하므로, 앱이 로그인 직후 `PUT /api/me/profile`로 올린다. |
| 푸시 알림 | Cloud Functions 대신 **서버에서 Firebase Admin으로 FCM 전송** | 이미 서버에 Firebase Admin SDK가 있다. 별도 배포 대상(Functions)이 사라진다. 단 **여유 시(Task 8)**로 내린다. |
| DM 상대 범위 | **같은 그룹 멤버끼리만** | 스펙 §6-④ "낯선 사용자 매칭 제외". uid만 알면 아무에게나 DM을 걸 수 있으면 그게 곧 낯선 사용자 연락이다. |
| 위치공유 권한 | "roomId를 아는 사람" → **방 멤버만** | Plan A Task 10이 "수용한 리스크"로 남겨 둔 부분을 이번에 닫는다. 채팅방 멤버 테이블이 생겼으므로 비용 없이 검사할 수 있다. |
| 방 목록 실시간 갱신 | **하지 않음(화면 진입 시 재조회)** | 열려 있는 방은 STOMP로 실시간이다. 목록 화면의 미리보기·안 읽은 수는 진입·당겨서 새로고침 때 갱신해도 시연에 지장이 없다. 사용자별 큐(`/user/queue`)는 v2로 미룬다. |

---

## Global Constraints

- **브랜치 전략**: 문서는 `docs/plan-d-server-chat`, 구현은 Task 단위 `feature/server-chat-*`, `feature/app-chat-*`. 대상 브랜치는 `master`(팀 합의로 `develop` 없이 운영), PR 2인 승인, Squash 머지.
- **커밋 메시지**: `feat(server): …`, `feat(app): …`, `docs(plans): …` — 저장소 관례.
- **패키지**: 서버 `com.travelfootsteps.chat`(신규), 앱 `app/lib/features/group/`.
- **마이그레이션 번호**: 현재 V9까지 사용 중. 이 계획서는 **V10~V12**를 쓴다. 착수 시점에 다른 사람이 V10을 먼저 쓰면 번호를 밀어서 맞춘다.
- **인증**: 모든 `/api/**`는 기존 `FirebaseAuthFilter`가 처리하고, 컨트롤러는 `authentication.getName()`으로 uid를 얻는다(TripController와 같은 방식). STOMP는 기존 `StompAuthChannelInterceptor`가 CONNECT에서 고정한 Principal을 쓴다. **클라이언트가 보낸 uid는 절대 믿지 않는다.**
- **권한 실패는 404**: 내가 멤버가 아닌 방은 "없는 방"과 똑같이 404로 답한다(TripController의 소유자 검사와 같은 원칙 — 방의 존재 여부를 흘리지 않는다).
- **실시간 위치는 저장하지 않는다.** 기존 `LocationRelayController`처럼 메모리 릴레이만 한다.
- **위치 송신은 앱 포그라운드에서만, 5초 간격**(스펙 §6-④). 앱 쪽 구현은 R3 소관.
- **제외 범위**: 임의 파일 전송, 낯선 사용자 매칭, 방 나가기·강퇴, 메시지 수정·삭제, 사용자별 방 목록 실시간 푸시.
- **자르는 순서 (스펙 §10)**: 시간이 부족하면 Task 8(푸시) → Task 6(사진) → Task 7(읽음) 순으로 미룬다. Task 1~5(그룹·채팅·DM)는 필수 기능(T2)이라 자르지 않는다.
- **테스트**: 서버는 기존 패턴(`@SpringBootTest` + Testcontainers Postgres + `StubTokenVerifier` + MockMvc). STOMP 인터셉터는 순수 단위 테스트(`LocationRelayControllerTest`와 같은 방식). 앱은 dio `StubHttpClientAdapter`와 가짜 소켓으로 서버 없이 검증한다. **서버 테스트에는 Docker가 필요하다.**

---

## 일정 (스펙 §9 Phase 2, W6~8)

| 주차 | Task | 게이트 |
|---|---|---|
| W6 (10/12~18) | 1 서버 그룹·프로필 · 2 서버 메시지·STOMP 권한 · 3 앱 그룹 목록·생성·참여 · 4 앱 채팅방 텍스트 | 그룹 채팅이 두 기기 사이에서 실시간으로 오간다 |
| W7 (10/19~25) | 5 DM(서버+앱) · 6 사진(서버+앱) | |
| W8 (10/26~11/1) | 7 읽음(서버+앱) · 8 푸시(여유 시) · 9 위치공유 연결 지원 | **M3 게이트** — 6개 기능이 기본 형태로 동작 |

---

## 데이터 모델

`V10__chat.sql` (Task 1~2), `V11__chat_dm.sql` (Task 5), `V12__chat_image.sql` (Task 6)에 나눠 만든다. 최종 형태는 아래와 같다.

```
app_user
  firebase_uid  VARCHAR(128) PK
  display_name  VARCHAR(100)
  photo_url     VARCHAR(500)
  fcm_token     VARCHAR(500)            -- Task 8
  updated_at    TIMESTAMPTZ NOT NULL

chat_room
  id                   BIGSERIAL PK
  type                 VARCHAR(10) NOT NULL   -- GROUP | DM
  name                 VARCHAR(50)            -- GROUP만. DM은 null(앱이 상대 이름으로 표시)
  invite_code          CHAR(6) UNIQUE         -- GROUP만
  dm_key               VARCHAR(260) UNIQUE    -- DM만. "작은uid|큰uid" — 같은 두 사람의 DM 중복 생성 방지
  last_message_id      BIGINT                 -- 목록 정렬·미리보기용 비정규화
  last_message_preview VARCHAR(100)
  last_message_at      TIMESTAMPTZ
  created_at           TIMESTAMPTZ NOT NULL
  CHECK (type IN ('GROUP','DM'))

chat_room_member
  room_id               BIGINT NOT NULL REFERENCES chat_room(id) ON DELETE CASCADE
  firebase_uid          VARCHAR(128) NOT NULL
  joined_at             TIMESTAMPTZ NOT NULL
  last_read_message_id  BIGINT               -- Task 7. null = 아직 아무것도 안 읽음
  PRIMARY KEY (room_id, firebase_uid)
  INDEX (firebase_uid)                       -- "내 방 목록"

chat_message
  id           BIGSERIAL PK
  room_id      BIGINT NOT NULL REFERENCES chat_room(id) ON DELETE CASCADE
  sender_uid   VARCHAR(128) NOT NULL
  type         VARCHAR(10) NOT NULL          -- TEXT | IMAGE (LOCATION은 스키마만 허용, UI 없음)
  text         VARCHAR(1000)
  image_path   VARCHAR(300)                  -- Task 6. 서버 디스크 상대 경로, 외부에 노출하지 않음
  created_at   TIMESTAMPTZ NOT NULL
  INDEX (room_id, id DESC)                   -- 최신순 페이지 조회
```

**초대 코드**: 대문자+숫자 중 헷갈리는 글자(`0 O 1 I L`)를 뺀 31자에서 6자리를 `SecureRandom`으로 뽑는다(약 8.9억 가지). UNIQUE 제약 위반 시 최대 5번 다시 뽑는다.

**안 읽은 개수** (Task 7):
```sql
SELECT count(*) FROM chat_message m
WHERE m.room_id = :roomId
  AND m.sender_uid <> :uid
  AND m.id > COALESCE(:lastReadMessageId, 0)
```
방 목록 응답에서 방마다 이 쿼리를 돌리면 N+1이 되므로, `GET /api/rooms`는 멤버 행과 `GROUP BY room_id` 한 번으로 모아서 센다(Task 7 Step 참고).

---

## API 계약

모두 로그인 필요. 응답 시각은 ISO-8601(OffsetDateTime). 멤버가 아닌 방에 대한 요청은 전부 **404**.

| 메서드·경로 | 요청 | 응답 | Task |
|---|---|---|---|
| `PUT /api/me/profile` | `{displayName, photoUrl}` | 204 | 1 |
| `POST /api/rooms` | `{name}` (1~50자) | 201 `RoomDetail` | 1 |
| `POST /api/rooms/join` | `{inviteCode}` | 200 `RoomDetail` (이미 멤버여도 200) / 404 코드 없음 | 1 |
| `GET /api/rooms` | — | `[RoomSummary]` 최근 메시지순 | 1, 7 |
| `GET /api/rooms/{id}` | — | `RoomDetail` | 1 |
| `GET /api/rooms/{id}/messages?before={id}&size=30` | `before` 없으면 최신부터 | `[Message]` **최신순(내림차순)**, size 최대 50 | 2 |
| `POST /api/rooms/{id}/messages` | `{text}` (1~1000자, 앞뒤 공백 제거 후) | 201 `Message` | 2 |
| `POST /api/rooms/dm` | `{peerUid}` | 200 `RoomDetail` (있으면 기존 방) / 404 같은 그룹 아님 | 5 |
| `POST /api/rooms/{id}/images` | multipart `file` (jpeg/png/webp, 5MB 이하) | 201 `Message` (type=IMAGE) | 6 |
| `GET /api/rooms/{id}/images/{messageId}` | — | 이미지 바이트 + `Content-Type`, `Cache-Control: private, max-age=86400` | 6 |
| `POST /api/rooms/{id}/read` | `{lastReadMessageId}` | 204 (기존 값보다 작으면 무시) | 7 |
| `PUT /api/me/fcm-token` | `{fcmToken}` | 204 | 8 |

```
RoomSummary { id, type, name, inviteCode, memberCount,
              lastMessagePreview, lastMessageAt, unreadCount,
              dmPeer: { uid, displayName, photoUrl } | null }      -- unreadCount는 Task 7 전까지 0
RoomDetail  { id, type, name, inviteCode,
              members: [{ uid, displayName, photoUrl, lastReadMessageId }] }
Message     { id, roomId, senderUid, type, text, imageUrl, createdAt }
              -- imageUrl은 "/api/rooms/{roomId}/images/{id}" 형태의 상대 경로. IMAGE가 아니면 null
```

**STOMP** (기존 `/ws` 엔드포인트, CONNECT 시 `Authorization: Bearer <ID Token>`)

| 방향 | 목적지 | 바디 | 권한 | Task |
|---|---|---|---|---|
| SUBSCRIBE | `/topic/rooms/{roomId}/messages` | `Message` | 방 멤버 | 2 |
| SUBSCRIBE | `/topic/rooms/{roomId}/read` | `{uid, lastReadMessageId}` | 방 멤버 | 7 |
| SUBSCRIBE | `/topic/group/{roomId}/location` (기존) | `{uid, lat, lng, ts}` | **방 멤버(신규)** | 2 |
| SEND | `/app/location` (기존) | `{roomId, lat, lng, ts}` | **방 멤버(신규)** | 2 |

`roomId`는 `chat_room.id`(숫자)를 문자열로 쓴다. 위치공유는 GROUP 방에서만 의미가 있지만 DM을 막을 이유도 없어 멤버 여부만 본다.

---

## File Structure

```
server/src/main/java/com/travelfootsteps/
├── chat/
│   ├── AppUser.java, AppUserRepository.java, ProfileController.java      Task 1, 8
│   ├── ChatRoom.java, ChatRoomRepository.java, RoomType.java            Task 1, 5
│   ├── ChatRoomMember.java, ChatRoomMemberRepository.java               Task 1, 7
│   ├── ChatMessage.java, ChatMessageRepository.java, MessageType.java   Task 2, 6
│   ├── InviteCodeGenerator.java                                        Task 1
│   ├── RoomService.java          방 생성·참여·DM·멤버십 검사(requireMember)   Task 1, 5
│   ├── MessageService.java       저장 + 방 비정규화 갱신 + 브로드캐스트        Task 2, 6, 7
│   ├── RoomController.java, MessageController.java                     Task 1, 2, 5~7
│   ├── ChatImageStorage.java     인터페이스 + LocalDiskChatImageStorage      Task 6
│   ├── ChatPushNotifier.java     인터페이스 + FcmChatPushNotifier + Noop     Task 8
│   ├── RoomSubscriptionInterceptor.java   SUBSCRIBE 멤버십 검사            Task 2
│   ├── ChatExceptionHandler.java, RoomNotFoundException.java           Task 1
│   └── dto/  (요청·응답 record)
├── location/
│   ├── WebSocketConfig.java          (Modify) 인터셉터 등록 추가            Task 2
│   └── LocationRelayController.java  (Modify) SEND 멤버십 검사             Task 2
└── resources/db/migration/V10__chat.sql, V11__chat_dm.sql, V12__chat_image.sql

server/src/test/java/com/travelfootsteps/chat/
├── RoomControllerTest.java, MessageControllerTest.java   (Testcontainers 통합)
├── InviteCodeGeneratorTest.java, RoomSubscriptionInterceptorTest.java (단위)
└── support/RecordingMessagingTemplate 또는 Mockito SimpMessagingTemplate

app/lib/features/group/
├── models/      room.dart, chat_message.dart
├── data/        chat_api.dart (dio), chat_socket.dart (인터페이스 + Stomp 구현), profile_sync.dart
├── providers/   room_providers.dart, chat_room_controller.dart (메시지 목록 Notifier)
├── group_page.dart, chat_room_page.dart     (Modify) 와이어프레임에 데이터 연결
├── create_group_sheet.dart, join_group_sheet.dart
└── (location_share_page.dart — R3 소관, Task 9에서 소켓 계층만 넘겨줌)

app/test/group/  chat_api_test.dart, chat_room_controller_test.dart, fake_chat_socket.dart, *_page_test.dart
docs/api-spec.md  (Modify) "9. 채팅" 섹션 추가 — Task 1, 2, 5~7에서 해당 부분씩
```

**분리 원칙**: 서버는 컨트롤러가 얇고 규칙(멤버십, DM 허용 범위, 읽음 단조 증가)은 `RoomService`·`MessageService`에 모은다 — STOMP 인터셉터와 REST가 **같은 `requireMember`**를 써야 권한 규칙이 두 군데로 갈라지지 않는다. 앱은 `data/`만 dio·STOMP를 알고, 화면은 provider만 본다(Phase 0의 `AuthRepository` 추상화와 같은 이유).

---

### Task 1: [서버] 프로필 + 그룹 생성·참여·목록

**브랜치:** `feature/server-chat-group`
**Files:** `V10__chat.sql`(app_user, chat_room, chat_room_member, chat_message 전부 — Task 2가 같은 마이그레이션을 쓴다), `AppUser*`, `ProfileController`, `ChatRoom*`, `ChatRoomMember*`, `RoomType`, `InviteCodeGenerator`, `RoomService`, `RoomController`, `ChatExceptionHandler`, `RoomNotFoundException`, 테스트 2개

**Interfaces:**
- Produces: `RoomService.requireMember(Long roomId, String uid)` — 멤버가 아니면 `RoomNotFoundException`(→ 404). **Task 2의 인터셉터·메시지 API, Task 5~7이 전부 이것을 쓴다.**
- Produces: `RoomService.isMember(Long roomId, String uid)` — 예외 없이 boolean(인터셉터용).

- [ ] **Step 1: 실패하는 테스트 작성** — `InviteCodeGeneratorTest`(6자리, 허용 문자만, 1만 번 생성 시 금지 문자 없음), `RoomControllerTest`:
  - 방을 만들면 201, 응답에 6자리 `inviteCode`, 만든 사람이 멤버로 들어 있다
  - 다른 사용자가 코드로 참여하면 멤버가 2명이 된다 / **같은 사람이 두 번 참여해도 멤버는 늘지 않고 200**
  - 없는 코드는 404, 소문자로 보내도 참여된다(대문자로 정규화)
  - `GET /api/rooms`는 내가 속한 방만 돌려준다(남의 방은 안 보인다)
  - **멤버가 아닌 사람의 `GET /api/rooms/{id}`는 404**
  - 이름이 비었거나 50자를 넘으면 400
  - `PUT /api/me/profile` 후 `RoomDetail.members[].displayName`에 반영된다 / 프로필을 안 올린 멤버는 `displayName: null`(앱이 "알 수 없음"으로 표시)
- [ ] **Step 2: 테스트 실패 확인** — `cd server && ./gradlew test --tests '*Room*' --tests '*InviteCode*'`
- [ ] **Step 3: `V10__chat.sql` 작성** — 위 "데이터 모델"의 네 테이블(Task 5·6 컬럼 `dm_key`, `image_path`는 각 Task의 마이그레이션에서 추가). 테이블마다 기존 마이그레이션처럼 **왜 이런 구조인지 주석**을 남긴다(특히 읽음을 멤버 행에 두는 이유).
- [ ] **Step 4: 엔티티·리포지토리** — `Trip`과 같은 스타일(`@NoArgsConstructor(access = PROTECTED)`, 정적 팩토리 `create(...)`, setter 없음). `ChatRoomMember`는 `@IdClass`로 복합 키.
- [ ] **Step 5: `InviteCodeGenerator`, `RoomService`, `RoomController`, `ProfileController`** — 생성은 `@Transactional`로 방+멤버를 함께 저장한다. 코드 충돌 재시도는 `DataIntegrityViolationException`을 잡아 최대 5회.
- [ ] **Step 6: 테스트 통과 + 전체 회귀** — `./gradlew test`
- [ ] **Step 7: `docs/api-spec.md`에 "9. 채팅" 섹션 신설**, 이 Task의 5개 엔드포인트를 기존 형식대로 추가
- [ ] **Step 8: 커밋** — `feat(server): 채팅 그룹 생성·초대 코드 참여·프로필 API`

---

### Task 2: [서버] 메시지 저장·조회 + STOMP 브로드캐스트 + 구독 권한

**브랜치:** `feature/server-chat-message`
**Files:** `ChatMessage*`, `MessageType`, `MessageService`, `MessageController`, `RoomSubscriptionInterceptor`, Modify `WebSocketConfig`, `LocationRelayController`, 테스트

**Interfaces:**
- Consumes: Task 1의 `RoomService.requireMember/isMember`, 기존 `SimpMessagingTemplate`
- Produces: `MessageService.send(roomId, uid, text): MessageResponse` — 저장 → `chat_room.last_message_*` 갱신 → `/topic/rooms/{id}/messages` 브로드캐스트. **브로드캐스트는 트랜잭션 커밋 후**에 한다(`TransactionSynchronization.afterCommit` 또는 `@TransactionalEventListener(AFTER_COMMIT)`) — 커밋 전에 보내면 롤백된 메시지가 상대 화면에 뜰 수 있다.

**구독 권한 인터셉터의 핵심:**
```java
// RoomSubscriptionInterceptor.preSend — StompAuthChannelInterceptor 다음에 등록한다.
// CONNECT에서 고정된 Principal은 SUBSCRIBE 프레임의 accessor.getUser()로 그대로 넘어온다.
if (StompCommand.SUBSCRIBE.equals(accessor.getCommand())) {
    Long roomId = RoomDestinations.parseRoomId(accessor.getDestination()); // 방 경로가 아니면 null
    if (roomId != null) {
        Principal user = accessor.getUser();
        if (user == null || !roomService.isMember(roomId, user.getName())) {
            throw new StompAuthenticationException("방 멤버가 아닙니다");
        }
    }
}
```
`RoomDestinations.parseRoomId`는 `/topic/rooms/{id}/messages`, `/topic/rooms/{id}/read`, `/topic/group/{id}/location` 세 형태만 인식하고, 숫자가 아니면 거부한다. **방 경로처럼 생겼는데 형식이 틀린 목적지도 거부**한다(허용 목록 방식 — 모르는 경로를 통과시키지 않는다).

- [ ] **Step 1: 실패하는 테스트 작성**
  - `MessageControllerTest`(통합): 보내면 201과 id·createdAt이 온다 / 공백만 있거나 1000자 초과면 400 / 멤버 아니면 404 / 조회는 최신순, `before`로 이전 페이지, `size` 상한 50 / 보낸 뒤 `GET /api/rooms`의 `lastMessagePreview`가 바뀐다 / **`SimpMessagingTemplate` 목에 `/topic/rooms/{id}/messages`로 한 번 전송된다**
  - `RoomSubscriptionInterceptorTest`(단위, `RoomService` 목): 멤버면 통과 / 비멤버면 예외 / Principal 없으면 예외 / 숫자 아닌 roomId 예외 / 방과 무관한 목적지(`/topic/other`)는 통과 / SUBSCRIBE가 아닌 프레임은 검사하지 않음
  - `LocationRelayControllerTest`(기존 수정): **비멤버의 SEND는 브로드캐스트하지 않는다**(기존 테스트 4개는 멤버 스텁으로 그대로 통과해야 한다)
- [ ] **Step 2: 테스트 실패 확인**
- [ ] **Step 3: 구현** — `MessageService`, `MessageController`, `RoomSubscriptionInterceptor`, `RoomDestinations`
- [ ] **Step 4: `WebSocketConfig.configureClientInboundChannel`에 인터셉터 추가** — 순서: `stompAuthChannelInterceptor`, `roomSubscriptionInterceptor`. 순서가 바뀌면 SUBSCRIBE 시점에 Principal이 없어 전부 거부된다는 주석을 남긴다.
- [ ] **Step 5: `LocationRelayController.relay`에 멤버십 검사 추가** — 비멤버면 조용히 버린다. 클래스 주석의 "의도적으로 생략한 것 — 그룹 멤버십" 단락을 "Plan D Task 2에서 닫음"으로 갱신한다.
- [ ] **Step 6: 수동 확인** — 서버를 띄우고 STOMP 클라이언트(예: 브라우저 콘솔의 `@stomp/stompjs`, 또는 Task 4 이후 앱 두 대)로 두 사용자가 같은 방을 구독한 뒤 REST로 보낸 메시지가 양쪽에 오는지, 비멤버의 SUBSCRIBE가 연결 종료로 끝나는지 본다.
- [ ] **Step 7: 테스트 통과 + 전체 회귀, api-spec 갱신**(메시지 2개 + STOMP 표)
- [ ] **Step 8: 커밋** — `feat(server): 채팅 메시지 저장·조회·STOMP 브로드캐스트와 방 구독 권한`

---

### Task 3: [앱] 프로필 동기화 + 그룹 목록·생성·참여

**브랜치:** `feature/app-chat-group`
**Files:** `models/room.dart`, `data/chat_api.dart`, `data/profile_sync.dart`, `providers/room_providers.dart`, `create_group_sheet.dart`, `join_group_sheet.dart`, Modify `group_page.dart`, `router.dart`, `main.dart`

**Interfaces:**
- Produces: `ChatApi`(dio) — `createRoom`, `joinRoom`, `myRooms`, `roomDetail`, `putProfile` (Task 4~7이 메서드를 이어 붙인다)
- Produces: `myRoomsProvider`(`FutureProvider<List<RoomSummary>>`), 라우트 **`/group/chat/:roomId`**(기존 고정 경로 `/group/chat` 교체)

- [ ] **Step 1: 실패하는 테스트** — `chat_api_test.dart`(`StubHttpClientAdapter` 재사용: 경로·메서드·바디·파싱, 404를 `RoomNotFound`로 변환), `group_page_test.dart`(가짜 `ChatApi`: 목록 표시, 빈 상태, 생성 시트 → 생성 후 목록 갱신, 잘못된 코드 오류 문구)
- [ ] **Step 2: 프로필 동기화** — `authStateProvider`가 로그인 사용자를 내보낼 때 `PUT /api/me/profile` 한 번. 실패해도 앱 흐름을 막지 않는다(로그만). `main.dart`의 루트 위젯에서 `ref.listen`.
- [ ] **Step 3: 모델·API·provider 구현**
- [ ] **Step 4: 와이어프레임 `group_page.dart`에 연결** — 하드코딩 목록을 `myRoomsProvider`로, `_InviteCodeCard`의 "초대 코드로 참여"를 참여 시트로, 상단에 "그룹 만들기". 방을 누르면 `/group/chat/{id}`. 당겨서 새로고침 = `ref.invalidate(myRoomsProvider)`. 방 상세 상단에 초대 코드 복사 버튼.
- [ ] **Step 5: 전체 검사** — `flutter analyze && flutter test`
- [ ] **Step 6: 실기기 확인** — 기기 A에서 그룹 생성 → 코드를 기기 B에 입력 → 양쪽 목록에 같은 방
- [ ] **Step 7: 커밋** — `feat(app): 그룹 목록·생성·초대 코드 참여와 프로필 동기화`

---

### Task 4: [앱] 채팅방 — 실시간 텍스트

**브랜치:** `feature/app-chat-room`
**Files:** `models/chat_message.dart`, `data/chat_socket.dart`, `providers/chat_room_controller.dart`, Modify `chat_room_page.dart`, `pubspec.yaml`(`stomp_dart_client`), 테스트 + `test/group/fake_chat_socket.dart`

**Interfaces:**
- Produces: `ChatSocket` 인터페이스 — `Future<void> connect()`, `Stream<ChatMessage> roomMessages(int roomId)`, `Stream<ReadEvent> roomReads(int roomId)`(Task 7), `Stream<Map<String,dynamic>> subscribe(String destination)`(Task 9에서 R3가 위치용으로 사용), `void send(String destination, Map body)`, `Future<void> disconnect()`
- Produces: `StompChatSocket` — 앱 전체에서 **연결 하나를 공유**한다(`chatSocketProvider`). URL은 `resolveBaseUrl`의 `http`를 `ws`로 바꾸고 `/ws`를 붙인다. CONNECT 헤더에 `currentIdToken()`. 연결이 끊기면 `stomp_dart_client`의 재연결을 쓰되, **재연결 때마다 새 토큰으로** CONNECT한다(ID Token은 1시간 만료).
- Produces: `ChatRoomController`(`Notifier`) — 상태 `{messages(최신순), hasMore, sending}`. 진입 시 REST로 최근 30개 → 소켓 구독. **REST 응답과 소켓 이벤트가 같은 메시지를 두 번 줄 수 있으므로 id로 중복 제거**한다(내가 보낸 메시지는 POST 응답과 브로드캐스트 둘 다 온다).

- [ ] **Step 1: 실패하는 테스트** — `chat_room_controller_test.dart`: 초기 로드 / 소켓 이벤트 추가 / **같은 id 두 번 → 하나만** / 이전 페이지 로드(`before`=가장 오래된 id) / 다른 방 이벤트 무시 / 전송 실패 시 상태 복구와 오류. 위젯 테스트: 내 말풍선·상대 말풍선 구분, 상대 이름(멤버 목록에서), 입력 후 전송
- [ ] **Step 2: 구현** — 스크롤은 `ListView(reverse: true)`로 최신이 아래. 맨 위 근처에서 이전 페이지 로드.
- [ ] **Step 3: 와이어프레임 `chat_room_page.dart`에 연결** — `_IncomingTextMessage`/`_OutgoingTextMessage` 등 기존 위젯을 재사용하고 하드코딩 데이터만 바꾼다. `_IncomingLocationMessage`는 이번 범위에서 쓰지 않는다(제외 범위).
- [ ] **Step 4: 화면 생명주기** — 방에 들어오면 구독, 나가면 구독 해제. 앱이 백그라운드로 가면 소켓을 끊고 돌아오면 재연결 후 **마지막으로 받은 id 이후를 REST로 다시 받아** 빈 구간을 메운다.
- [ ] **Step 5: 전체 검사 + 실기기 2대 종단 확인** — 한쪽에서 보낸 메시지가 다른 쪽에 1초 안에 뜬다 / 비행기 모드 후 복귀 시 놓친 메시지가 채워진다
- [ ] **Step 6: 커밋** — `feat(app): 채팅방 실시간 텍스트 송수신`

> **W6 체크포인트**: Task 1~4가 끝나면 그룹 채팅이 시연 가능하다. 여기까지가 이번 계획에서 가장 중요한 덩어리다.

---

### Task 5: [서버+앱] 1:1 DM

**브랜치:** `feature/server-chat-dm`, `feature/app-chat-dm`
**Files:** 서버 `V11__chat_dm.sql`(`dm_key` 컬럼 + UNIQUE), `RoomService.findOrCreateDm`, `RoomController` · 앱 `ChatApi.openDm`, 그룹 상세의 멤버 목록에 "메시지 보내기"

- [ ] **Step 1: 서버 테스트** — 같은 그룹 멤버에게 DM → 방 생성, 두 사람만 멤버 / **같은 요청을 다시 하면 같은 방 id**(양쪽 어느 쪽이 요청해도) / 같은 그룹이 아니면 404 / 자기 자신에게는 400 / DM 방은 `inviteCode`가 없고 코드로 참여할 수 없다
- [ ] **Step 2: 서버 구현** — `dm_key = min(uid)|max(uid)`. 동시에 두 요청이 와서 UNIQUE 위반이 나면 기존 방을 다시 조회해 돌려준다.
- [ ] **Step 3: 앱** — 방 목록에서 DM은 상대 이름·사진으로 표시(`dmPeer`), 그룹 상세 멤버 행에서 DM 열기. 채팅 화면은 Task 4 그대로 재사용.
- [ ] **Step 4: 검사·커밋** — `feat(server): 같은 그룹 멤버 간 1:1 DM`, `feat(app): DM 열기와 목록 표시`

---

### Task 6: [서버+앱] 사진 전송 *(자르는 순서 2번째)*

**브랜치:** `feature/server-chat-image`, `feature/app-chat-image`
**Files:** 서버 `V12__chat_image.sql`(`image_path`), `ChatImageStorage`(인터페이스) + `LocalDiskChatImageStorage`, `MessageController` 두 엔드포인트, `application.yml` · 앱 `ChatApi.sendImage`, 첨부 버튼, 이미지 말풍선

**서버 저장 규칙:**
- 설정 `chat.image-dir`(기본 `./data/chat-images`, 배포 시 VM 경로). 파일명은 **서버가 만든 UUID**만 쓴다 — 사용자가 보낸 파일명은 경로 조작(`../`) 위험이 있어 저장에 쓰지 않는다.
- 허용 형식은 **파일 앞부분 바이트(매직 넘버)로 판정**한다(JPEG `FF D8 FF`, PNG `89 50 4E 47`, WEBP `RIFF....WEBP`). 클라이언트가 보낸 `Content-Type`은 믿지 않는다.
- `spring.servlet.multipart.max-file-size: 5MB`, `max-request-size: 6MB`. 초과 시 413.
- **배포 메모**: Nginx 기본 `client_max_body_size`가 1MB라 그대로면 사진 업로드가 413으로 막힌다. 배포 계획서(`2026-09-14-oracle-cloud-deployment.md`)가 만들 `deploy/nginx.conf`에 `client_max_body_size 6m;`이 들어가야 한다(아직 파일이 없으므로 R1에게 배포 계획서 반영을 요청).
- 테스트에서는 `ChatImageStorage`를 임시 디렉터리(`@TempDir`) 구현으로 바꾼다.

- [ ] **Step 1: 서버 테스트** — JPEG 업로드 → IMAGE 메시지·브로드캐스트 / 텍스트 파일을 `.jpg`로 위장 → 415 / 5MB 초과 → 413 / 멤버는 내려받기 200·올바른 Content-Type / **비멤버는 404** / 다른 방의 messageId로 요청 → 404
- [ ] **Step 2: 서버 구현** — 저장 실패 시 DB에 메시지를 남기지 않는다(파일 저장 → 성공 시 메시지 저장, 메시지 저장 실패 시 파일 삭제).
- [ ] **Step 3: 앱** — `image_picker`로 고를 때 `maxWidth: 1600, imageQuality: 80`으로 줄여 올린다(대부분 1MB 이하). 이미지는 `Image.network(url, headers: {'Authorization': 'Bearer …'})`. 업로드 중에는 자리표시 말풍선, 실패 시 재시도 버튼.
- [ ] **Step 4: 검사·실기기 확인·커밋**

---

### Task 7: [서버+앱] 읽음 표시 *(자르는 순서 3번째)*

**브랜치:** `feature/server-chat-read`, `feature/app-chat-read`
**Files:** 서버 `ChatRoomMember.markRead`, `MessageController` read 엔드포인트, `GET /api/rooms`의 `unreadCount` · 앱 `ChatApi.markRead`, 방 목록 배지, 말풍선 옆 안 읽은 사람 수

- [ ] **Step 1: 서버 테스트** — read 후 해당 방 `unreadCount` 0 / **더 작은 id로 read 해도 값이 줄지 않는다** / 다른 방의 메시지 id로는 400 / 내가 보낸 메시지는 안 읽은 수에 안 들어간다 / read 시 `/topic/rooms/{id}/read`로 `{uid, lastReadMessageId}` 브로드캐스트 / `GET /api/rooms`가 방 여러 개의 안 읽은 수를 **쿼리 한 번**으로 센다(테스트에서 Hibernate statistics로 쿼리 수 확인)
- [ ] **Step 2: 서버 구현** — 단조 증가는 SQL로 보장한다: `UPDATE chat_room_member SET last_read_message_id = :id WHERE room_id = :roomId AND firebase_uid = :uid AND (last_read_message_id IS NULL OR last_read_message_id < :id)`.
- [ ] **Step 3: 앱** — 채팅방이 화면에 보이는 동안 가장 최근 메시지 id로 read를 보낸다(새 메시지가 올 때마다 보내지 말고 **1초 디바운스**). 각 메시지 옆에 "이 메시지를 아직 안 읽은 멤버 수" = `members.where((m) => m.uid != sender && (m.lastReadMessageId ?? 0) < message.id).length`, 0이면 표시 안 함. read 이벤트를 받으면 해당 멤버 값만 갱신.
- [ ] **Step 4: 검사·커밋**

---

### Task 8: [서버+앱] 새 메시지 푸시 알림 *(여유 시 — 가장 먼저 자른다)*

- 서버: `ChatPushNotifier` 인터페이스 + `FcmChatPushNotifier`(기존 `FirebaseApp` 빈으로 `FirebaseMessaging.getInstance(app)`) + 테스트용 `Noop`. `MessageService`가 커밋 후 발신자를 뺀 멤버의 `fcm_token`으로 보낸다. 전송 실패(토큰 만료 등)는 로그만 남기고 채팅 흐름을 막지 않는다. 만료 응답(`UNREGISTERED`)이면 그 토큰을 지운다.
- 앱: `firebase_messaging` 추가, 권한 요청, `PUT /api/me/fcm-token`, 알림을 누르면 `/group/chat/{roomId}`. **지금 그 방을 보고 있으면 알림을 띄우지 않는다.**
- 테스트: 서버는 `ChatPushNotifier` 목으로 "발신자 제외 멤버에게만, 커밋 후에" 호출되는지. 앱은 라우팅 함수 단위 테스트.

---

### Task 9: [서버 완료 확인 + R3 연결 지원] 위치공유

위치공유 **서버 권한**은 Task 2에서 끝난다. 이 Task는 R3가 위치공유 화면(`location_share_page.dart`)을 만들 때 쓸 수 있도록 넘겨주는 작업이다.

- [ ] **Step 1: R3와 소유권 확정** — 스펙 §8대로 위치공유 앱 클라이언트는 R3. 초판 Plan D Task 8(5초 틱, 포그라운드 감시, 지도 마커)의 내용은 git 이력에서 참고 자료로 넘긴다.
- [ ] **Step 2: 소켓 계층 공유** — R3는 STOMP 연결을 새로 만들지 않고 Task 4의 `chatSocketProvider`를 쓴다: `subscribe('/topic/group/$roomId/location')`, `send('/app/location', {...})`. 연결 하나를 공유해야 토큰 갱신·재연결 로직이 두 벌이 되지 않는다.
- [ ] **Step 3: 방 선택 연결** — 위치공유 화면은 그룹 방 id가 필요하다. `myRoomsProvider`에서 GROUP 방을 고르게 하거나, 채팅방 상단 위치 아이콘에서 `roomId`를 넘겨 연다(라우트 `/group/location/:roomId`).
- [ ] **Step 4: 종단 확인(R2·R3 함께)** — 멤버 두 명은 서로의 마커를 보고, 비멤버 계정은 구독이 거부된다.

---

## Self-Review

**1. 스펙 커버리지 (§6-④)**

| 스펙 항목 | Task |
|---|---|
| 6자리 초대 코드 그룹 생성/참여 | 1, 3 |
| 그룹 채팅 | 2, 4 |
| 1:1 DM | 5 |
| 사진 전송 | 6 (저장소만 Firebase Storage → 서버 디스크로 변경) |
| 읽음 표시(메시지마다 쓰지 않음) | 7 (`lastReadAt` → `last_read_message_id`) |
| 실시간 위치(포그라운드 5초, 미저장, ON/OFF 토글) | 서버 권한 2, 앱 클라이언트는 R3(9) |
| 위치 공유 메시지(1회성 핀) | 스키마만 허용(`LOCATION`), UI 없음 — 초판과 같은 판단 |
| 제외: 임의 파일, 낯선 사용자 매칭 | DM을 같은 그룹 멤버로 제한(5), 업로드 형식 제한(6) |

**2. 스펙 문서와 달라지는 곳 (스펙 갱신 필요)** — §2·§3 아키텍처 그림의 "Firestore(채팅)·Storage(사진)", §7의 Firestore 스키마, §8 R2 산출물의 "Firestore 채팅". 이 계획서가 승인되면 스펙 §12 결정 기록에 한 줄 추가하고 위 세 곳을 고친다.

**3. 다른 계획서·코드와의 접점**
- Plan A Task 10 `LocationRelayController` 주석의 "의도적으로 생략한 멤버십 검증" → Task 2에서 해소, 주석 갱신
- 배포 계획서의 `deploy/nginx.conf`(아직 미생성) 업로드 크기 → Task 6 착수 전 R1에게 요청
- `docs/api-spec.md` → Task 1·2·5·6·7에서 순차 추가

**4. 일관성 확인** — `RoomService.requireMember`/`isMember`(Task 1) → Task 2 인터셉터·메시지 API, Task 5~7에서 같은 이름으로 사용. 앱 `ChatApi`는 Task 3에서 만들고 Task 4~8이 메서드를 덧붙인다. `chatSocketProvider`는 Task 4에서 만들고 Task 7(읽음)과 Task 9(R3 위치)가 재사용한다. 라우트는 Task 3에서 `/group/chat/:roomId`로 바꾼 뒤 Task 5·8이 그대로 쓴다.

**5. 열어 둔 질문 (리뷰 때 결정)**
- 방 나가기가 정말 필요 없는가? 시연에서 "그룹을 잘못 만들었을 때"가 나오면 필요해진다. 필요하면 Task 1에 `DELETE /api/rooms/{id}/members/me`를 추가한다(약 반나절).
- 사진 보관 기간 — 캡스톤 기간에는 무기한, VM 디스크(Always Free 블록 볼륨)가 넉넉하므로 정리 배치는 만들지 않는다.
