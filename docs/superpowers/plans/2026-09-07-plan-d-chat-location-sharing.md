# Plan D — 앱: 그룹 채팅(그룹→DM→사진→읽음) + 실시간 위치공유 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 6자리 초대 코드로 여행 그룹을 만들고 참여할 수 있고, 그 그룹 안에서 그룹 채팅 → 1:1 DM → 사진 전송 → 읽음 표시 순으로 채팅 기능이 단계적으로 동작하며, 새 메시지 도착 시 푸시 알림이 오고, 그룹원끼리 앱이 켜져 있는 동안 5초 간격으로 서로의 실시간 위치를 지도에서 볼 수 있다.

**Architecture:** 채팅은 Firestore(`rooms/{roomId}`, `rooms/{roomId}/messages/{msgId}`)를 직접 구독하는 실시간 스트림으로 구현한다. 사진은 Firebase Storage에 올리고 다운로드 URL만 메시지 문서에 저장한다. 읽음 표시는 메시지마다 쓰지 않고 방 문서의 `lastReadAt{uid: timestamp}` 맵 하나만 갱신한다. 새 메시지 도착 푸시는 Firestore `onDocumentCreated` Cloud Function이 발신자를 제외한 참가자의 `fcmToken`으로 FCM을 보낸다. 실시간 위치공유는 Firestore를 전혀 쓰지 않고 Spring 서버의 STOMP WebSocket 릴레이(Plan A 범위, 이미 스펙에 정의되어 존재한다고 가정)에 좌표를 보내고 받는다 — 영속화하지 않는다.

**Tech Stack:** Flutter 3.x / Riverpod / go_router · cloud_firestore, firebase_storage, firebase_messaging, image_picker, stomp_dart_client, flutter_local_notifications, geolocator, google_maps_flutter · Firebase Cloud Functions (Node.js/TypeScript, 2nd gen) · fake_cloud_firestore(테스트)

**Spec:** `docs/superpowers/specs/2026-09-06-overseas-travel-app-design.md` §3, §6-④, §7
**선행 계획서:** `docs/superpowers/plans/2026-09-06-phase0-foundation.md` (Task 7 `GroupPage` 껍데기, Task 8 `AuthRepository`/`authStateProvider`, Task 9 `apiClientProvider`)

## Global Constraints

- **선행 조건**: Phase 0의 Task 7~9가 끝나 있어야 한다 — `AuthRepository`, `authStateProvider`, `createRouter`, `apiClientProvider`가 이미 존재한다고 가정하고 그 위에 이어 짓는다. 이 계획서는 그것들을 재구현하지 않는다.
- **Android 전용.** iOS 빌드 설정은 손대지 않는다. (스펙 전체 제약)
- **비밀정보를 커밋하지 않는다.** `google-services.json`, `firebase-service-account.json`, `.env`는 이미 `.gitignore`에 있다. Cloud Functions 배포에 쓰는 서비스 계정도 커밋하지 않는다.
- **브랜치 전략**: `feature/*`에서 시작해 `develop`으로 PR, 2인 승인. 매주 금요일 `develop` 머지.
- **패키지 루트**: `com.travelfootsteps` / Dart 패키지명 `app` (import는 `package:app/...`).
- **Firestore/Storage 리전**: `asia-northeast3` (Phase 0 Task 2에서 이미 이 리전으로 생성됨).
- **인증 규칙 (스펙 §3)**: 화면은 `signInWithGoogle()`을 직접 호출하지 않는다. 사용자 식별은 전부 `authStateProvider`의 `AppUser.uid`로 한다.
- **읽음 표시는 메시지 단위로 쓰지 않는다.** 방 문서의 `lastReadAt{uid: timestamp}` 하나만 갱신한다 (스펙 §6-④ — write 비용을 참가자 수(N)당 1회에서 메시지마다가 아니라 "읽었을 때 1회"로 줄이기 위함).
- **실시간 위치는 저장하지 않는다.** Firestore에도, PostgreSQL에도 쓰지 않는다. 서버 메모리 릴레이(STOMP)만 거친다.
- **위치 송신은 앱이 포그라운드일 때만, 5초 간격으로.** 백그라운드로 전환되면 즉시 멈춘다.
- **위치공유 ON/OFF 토글은 그룹 화면에서 상시 보인다.** 기본값은 OFF.
- **제외 범위 (스펙 §6-④, §11)**: 임의 파일 전송, 낯선 사용자 매칭, 개인 발걸음 기록(Plan C 소관), 고빈도(초 단위) 이동 경로의 영속 저장.
- **여유가 없어질 때 자르는 순서 (스펙 §10)**: ⑦ 환율/지갑·⑥ 주변정보 심화 → 음성 번역 → 사진 전송 → 읽음 표시. 이 계획서 안에서 시간이 부족하면 Task 5(사진), Task 6(읽음)을 이 순서로 뒤로 미룬다. Task 1~4(그룹·채팅 코어)와 Task 8(위치공유)은 필수 6개 기능에 직접 걸려 있으므로 자르지 않는다.

---

## File Structure

```
travel-footsteps/
├── firebase.json                                Firebase CLI 설정 (Task 2)
├── firestore.rules                              보안 규칙 (Task 2)
├── firestore.indexes.json                       복합 인덱스 (Task 2, 6)
├── functions/                                   Cloud Functions (Task 7)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/index.ts                             새 메시지 → FCM 푸시 트리거
└── app/
    ├── pubspec.yaml                              (Modify) 아래 "의존성" 참고
    ├── lib/
    │   ├── main.dart                             (Modify) 유저 동기화 리스너, FCM 백그라운드 핸들러
    │   ├── router.dart                           (Modify) 그룹 생성/참여/채팅방/지도 라우트 추가
    │   └── features/
    │       └── group/
    │           ├── models/
    │           │   ├── chat_room.dart            ChatRoom, RoomType
    │           │   └── chat_message.dart         ChatMessage, MessageType
    │           ├── data/
    │           │   ├── user_sync_service.dart    users/{uid} upsert (+ fcmToken, Task 7에서 확장)
    │           │   ├── group_repository.dart      방 생성/참여/목록/lastReadAt 갱신
    │           │   ├── chat_repository.dart       메시지 스트림/전송(텍스트·사진)
    │           │   ├── image_uploader.dart        인터페이스 + Storage 구현체 + Fake
    │           │   └── location_share_client.dart 인터페이스 + STOMP 구현체 + Fake
    │           ├── providers/
    │           │   ├── group_providers.dart
    │           │   ├── chat_providers.dart
    │           │   └── location_share_providers.dart
    │           ├── controllers/
    │           │   └── location_share_controller.dart  5초 틱 + 포그라운드 감시
    │           ├── screens/
    │           │   ├── group_page.dart            (Modify) 내 그룹/DM 목록
    │           │   ├── create_group_page.dart
    │           │   ├── join_group_page.dart
    │           │   ├── chat_room_page.dart
    │           │   └── group_location_map_page.dart
    │           └── widgets/
    │               ├── message_bubble.dart
    │               └── unread_dot.dart
    └── test/
        └── group/
            ├── user_sync_service_test.dart
            ├── group_repository_test.dart
            ├── chat_repository_test.dart
            ├── image_uploader_test.dart
            ├── unread_test.dart
            ├── location_share_client_test.dart
            └── location_share_controller_test.dart
```

**분리 원칙**: `data/`는 Firestore·Storage·WebSocket과 직접 대화하는 유일한 층이다. `screens/`와 `controllers/`는 `data/`의 인터페이스만 알고 구체 구현(진짜 Firestore인지 Fake인지)을 모른다 — Phase 0의 `TokenVerifier`, `AuthRepository` 추상화와 같은 이유다: 테스트가 실제 네트워크·Firebase를 타지 않게 하기 위해서다.

### 의존성 (Task 1 Step 0에서 한 번에 추가)

```bash
cd app
flutter pub add cloud_firestore firebase_storage firebase_messaging image_picker stomp_dart_client geolocator flutter_local_notifications
flutter pub add --dev fake_cloud_firestore
```

`google_maps_flutter`는 Plan C(지도·발걸음·위치공유 클라이언트, R3)가 이미 추가했을 가능성이 높다. `flutter pub add google_maps_flutter`는 이미 있으면 버전을 맞추기만 하고 실패하지 않으므로 Task 8에서 다시 추가해도 안전하다. `geolocator` 역시 Plan C와 겹칠 수 있다 — 겹쳐도 `pub add`는 멱등이다.

> **Plan C와의 관계 (읽고 넘어갈 것)**: Phase 0 문서의 "다음 계획서" 표는 "위치공유 클라이언트"를 Plan C(R3)의 산출물로 적어 두었다. 이 계획서(Plan D)는 지시받은 범위에 따라 그룹 채팅 화면 안에 있는 실시간 위치공유(§6-④, STOMP)를 직접 구현한다. 두 계획서가 동시에 실행되면 STOMP 클라이언트가 중복 구현될 수 있으므로, **실행 전 R2·R3가 이 부분의 소유권을 한쪽으로 확정**해야 한다. 이 계획서는 지도 "표시" 위젯만 Plan C 산출물을 재사용 가능하면 재사용하고(Task 8 참고), 불가능하면 `google_maps_flutter`로 최소 자체 위젯을 그대로 쓴다 — 어느 쪽이든 동작하도록 작성했다.

---

### Task 1: Firestore 데이터 모델 + 유저 동기화 + 그룹 생성/참여(초대 코드)

**Files:**
- Create: `app/lib/features/group/models/chat_room.dart`
- Create: `app/lib/features/group/models/chat_message.dart`
- Create: `app/lib/features/group/data/user_sync_service.dart`
- Create: `app/lib/features/group/data/group_repository.dart`
- Create: `app/lib/features/group/providers/group_providers.dart`
- Create: `app/lib/features/group/screens/create_group_page.dart`
- Create: `app/lib/features/group/screens/join_group_page.dart`
- Modify: `app/lib/features/group/screens/group_page.dart` (Phase 0 Task 7의 껍데기를 교체)
- Modify: `app/lib/router.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/group/user_sync_service_test.dart`
- Test: `app/test/group/group_repository_test.dart`

**Interfaces:**
- Consumes: Phase 0의 `authStateProvider` (`StreamProvider<AppUser?>`), `AppUser.uid/displayName/photoUrl`
- Produces:
  - `ChatRoom` — `id, type(RoomType), name, inviteCode, participants(List<String>), lastMessage, lastMessageAt(Timestamp?), lastReadAt(Map<String, Timestamp>)`, `factory ChatRoom.fromDoc(...)`, `Map<String, dynamic> toCreateMap(...)`
  - `RoomType` enum — `group, dm`, `toFirestore()`/`fromFirestore(String)`
  - `GroupRepository` — `Future<String> createGroup({required String name, required String creatorUid})` (6자리 초대 코드 자동 생성, roomId 반환), `Future<String> joinGroupByCode({required String code, required String uid})` (roomId 반환, 존재하지 않으면 `GroupNotFoundException`, 이미 멤버면 그대로 roomId 반환), `Stream<List<ChatRoom>> myRoomsStream(String uid)`
  - `UserSyncService.syncProfile(AppUser user)` — `users/{uid}` merge upsert. Task 7이 여기에 `fcmToken` 필드를 이어서 갱신한다.
  - `groupRepositoryProvider`, `firestoreProvider` (`Provider<FirebaseFirestore>`), `myRoomsProvider` (`StreamProvider<List<ChatRoom>>`)
  - 라우트: `AppRoutes.groupCreate`, `AppRoutes.groupJoin`, `AppRoutes.roomDetail(String roomId)` — Task 3, 4가 이 경로로 `context.push`한다.

- [ ] **Step 1: 의존성 추가**

```bash
cd app
flutter pub add cloud_firestore firebase_storage firebase_messaging image_picker stomp_dart_client geolocator flutter_local_notifications
flutter pub add --dev fake_cloud_firestore
```

- [ ] **Step 2: 모델 실패하는 테스트 없이 먼저 정의 (데이터 클래스는 TDD 대상에서 제외 — 로직이 없다)**

`app/lib/features/group/models/chat_room.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum RoomType {
  group,
  dm;

  String toFirestore() => name.toUpperCase();

  static RoomType fromFirestore(String value) =>
      RoomType.values.firstWhere((e) => e.name.toUpperCase() == value);
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.type,
    required this.name,
    this.inviteCode,
    required this.participants,
    this.lastMessage,
    this.lastMessageAt,
    this.lastReadAt = const {},
  });

  final String id;
  final RoomType type;
  final String name;
  final String? inviteCode;
  final List<String> participants;
  final String? lastMessage;
  final Timestamp? lastMessageAt;
  final Map<String, Timestamp> lastReadAt;

  factory ChatRoom.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawLastReadAt = (data['lastReadAt'] as Map<String, dynamic>?) ?? {};
    return ChatRoom(
      id: doc.id,
      type: RoomType.fromFirestore(data['type'] as String),
      name: data['name'] as String,
      inviteCode: data['inviteCode'] as String?,
      participants: List<String>.from(data['participants'] as List),
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: data['lastMessageAt'] as Timestamp?,
      lastReadAt: rawLastReadAt.map((k, v) => MapEntry(k, v as Timestamp)),
    );
  }

  /// 읽지 않은 메시지가 있는지: 마지막 메시지 시각이 내가 마지막으로 읽은 시각보다 뒤인가.
  bool hasUnreadFor(String uid) {
    final lastMsg = lastMessageAt;
    if (lastMsg == null) return false;
    final myLastRead = lastReadAt[uid];
    if (myLastRead == null) return true;
    return lastMsg.compareTo(myLastRead) > 0;
  }
}
```

`app/lib/features/group/models/chat_message.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  image,
  location;

  String toFirestore() => name.toUpperCase();

  static MessageType fromFirestore(String value) =>
      MessageType.values.firstWhere((e) => e.name.toUpperCase() == value);
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.type,
    this.text,
    this.imageUrl,
    this.lat,
    this.lng,
    required this.createdAt,
  });

  final String id;
  final String senderUid;
  final MessageType type;
  final String? text;
  final String? imageUrl;
  final double? lat;
  final double? lng;
  final Timestamp createdAt;

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ChatMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String,
      type: MessageType.fromFirestore(data['type'] as String),
      text: data['text'] as String?,
      imageUrl: data['imageUrl'] as String?,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      createdAt: data['createdAt'] as Timestamp,
    );
  }
}
```

`hasUnreadFor`가 순수 함수라 여기서 바로 검증할 수 있다. `app/test/group/unread_test.dart`를 지금 작성해 둔다 (Task 6까지 안 미룬다 — 로직 자체는 지금 만들어졌기 때문).

```dart
import 'package:app/features/group/models/chat_room.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatRoom.hasUnreadFor', () {
    test('마지막 메시지가 없으면 안읽음 없음', () {
      const room = ChatRoom(id: 'r1', type: RoomType.group, name: '그룹', participants: ['u1']);
      expect(room.hasUnreadFor('u1'), isFalse);
    });

    test('한 번도 읽은 적 없으면 안읽음', () {
      final room = ChatRoom(
        id: 'r1', type: RoomType.group, name: '그룹', participants: ['u1'],
        lastMessageAt: Timestamp.fromMillisecondsSinceEpoch(1000),
      );
      expect(room.hasUnreadFor('u1'), isTrue);
    });

    test('마지막 읽은 시각이 마지막 메시지보다 이후면 안읽음 없음', () {
      final room = ChatRoom(
        id: 'r1', type: RoomType.group, name: '그룹', participants: ['u1'],
        lastMessageAt: Timestamp.fromMillisecondsSinceEpoch(1000),
        lastReadAt: {'u1': Timestamp.fromMillisecondsSinceEpoch(2000)},
      );
      expect(room.hasUnreadFor('u1'), isFalse);
    });

    test('마지막 읽은 시각이 마지막 메시지보다 이전이면 안읽음', () {
      final room = ChatRoom(
        id: 'r1', type: RoomType.group, name: '그룹', participants: ['u1'],
        lastMessageAt: Timestamp.fromMillisecondsSinceEpoch(2000),
        lastReadAt: {'u1': Timestamp.fromMillisecondsSinceEpoch(1000)},
      );
      expect(room.hasUnreadFor('u1'), isTrue);
    });
  });
}
```

```bash
cd app && flutter test test/group/unread_test.dart
```

기대: 4개 테스트 모두 PASS (모델과 동시에 구현했으므로 실패 단계 없이 바로 통과 — 순수 데이터 로직이라 인터페이스 자체가 테스트 대상이다).

- [ ] **Step 3: `UserSyncService` 실패하는 테스트 작성**

`app/test/group/user_sync_service_test.dart`:

```dart
import 'package:app/core/auth/app_user.dart';
import 'package:app/features/group/data/user_sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserSyncService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = UserSyncService(firestore);
  });

  test('최초 로그인 시 users/{uid} 문서를 생성한다', () async {
    const user = AppUser(uid: 'uid-1', displayName: '조영진', photoUrl: 'https://x/y.png');

    await service.syncProfile(user);

    final doc = await firestore.collection('users').doc('uid-1').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['displayName'], '조영진');
    expect(doc.data()!['photoUrl'], 'https://x/y.png');
  });

  test('displayName이 null인 이메일 가입 사용자도 upsert 된다', () async {
    const user = AppUser(uid: 'uid-2');

    await service.syncProfile(user);

    final doc = await firestore.collection('users').doc('uid-2').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['displayName'], isNull);
  });

  test('재로그인 시 기존 필드를 덮어쓰지 않고 병합한다', () async {
    await firestore.collection('users').doc('uid-3').set({'fcmToken': 'token-abc'});
    const user = AppUser(uid: 'uid-3', displayName: '재로그인');

    await service.syncProfile(user);

    final doc = await firestore.collection('users').doc('uid-3').get();
    expect(doc.data()!['fcmToken'], 'token-abc');
    expect(doc.data()!['displayName'], '재로그인');
  });
}
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd app && flutter test test/group/user_sync_service_test.dart
```

기대: 컴파일 실패 — `UserSyncService` 심볼을 찾을 수 없음.

- [ ] **Step 5: `UserSyncService` 구현**

`app/lib/features/group/data/user_sync_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/auth/app_user.dart';

/// users/{uid} 문서를 로그인 방식과 무관하게 upsert한다 (스펙 §3 규칙 3).
/// merge: true로 써서 fcmToken 등 다른 필드를 덮어쓰지 않는다.
class UserSyncService {
  UserSyncService(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> syncProfile(AppUser user) {
    return _firestore.collection('users').doc(user.uid).set({
      'displayName': user.displayName,
      'photoUrl': user.photoUrl,
    }, SetOptions(merge: true));
  }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/group/user_sync_service_test.dart
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 7: `GroupRepository` 실패하는 테스트 작성**

`app/test/group/group_repository_test.dart`:

```dart
import 'package:app/features/group/data/group_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late GroupRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = GroupRepository(firestore);
  });

  test('그룹 생성 시 6자리 초대 코드와 방을 만들고 생성자를 참가자로 넣는다', () async {
    final roomId = await repository.createGroup(name: '오사카 여행', creatorUid: 'uid-1');

    final room = await firestore.collection('rooms').doc(roomId).get();
    expect(room.data()!['type'], 'GROUP');
    expect(room.data()!['name'], '오사카 여행');
    expect(room.data()!['participants'], ['uid-1']);
    final code = room.data()!['inviteCode'] as String;
    expect(code.length, 6);
    expect(code, code.toUpperCase());

    final inviteDoc = await firestore.collection('inviteCodes').doc(code).get();
    expect(inviteDoc.data()!['roomId'], roomId);
  });

  test('초대 코드로 참여하면 참가자 목록에 추가된다', () async {
    final roomId = await repository.createGroup(name: '방콕', creatorUid: 'uid-1');
    final room = await firestore.collection('rooms').doc(roomId).get();
    final code = room.data()!['inviteCode'] as String;

    final joinedRoomId = await repository.joinGroupByCode(code: code, uid: 'uid-2');

    expect(joinedRoomId, roomId);
    final updated = await firestore.collection('rooms').doc(roomId).get();
    expect(updated.data()!['participants'], containsAll(['uid-1', 'uid-2']));
  });

  test('이미 멤버인 사람이 같은 코드로 다시 참여해도 중복 추가되지 않는다', () async {
    final roomId = await repository.createGroup(name: '방콕', creatorUid: 'uid-1');
    final code = (await firestore.collection('rooms').doc(roomId).get()).data()!['inviteCode'] as String;

    await repository.joinGroupByCode(code: code, uid: 'uid-1');

    final updated = await firestore.collection('rooms').doc(roomId).get();
    expect((updated.data()!['participants'] as List).length, 1);
  });

  test('존재하지 않는 코드로 참여하면 예외를 던진다', () async {
    expect(
      () => repository.joinGroupByCode(code: 'ZZZZZZ', uid: 'uid-2'),
      throwsA(isA<GroupNotFoundException>()),
    );
  });

  test('myRoomsStream은 내가 참가자인 방만 방출한다', () async {
    final roomA = await repository.createGroup(name: 'A', creatorUid: 'uid-1');
    await repository.createGroup(name: 'B', creatorUid: 'uid-2');

    final rooms = await repository.myRoomsStream('uid-1').first;

    expect(rooms.map((r) => r.id), [roomA]);
  });
}
```

- [ ] **Step 8: 테스트 실패 확인**

```bash
cd app && flutter test test/group/group_repository_test.dart
```

기대: 컴파일 실패 — `GroupRepository` 심볼을 찾을 수 없음.

- [ ] **Step 9: `GroupRepository` 구현**

`app/lib/features/group/data/group_repository.dart`:

```dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_room.dart';

class GroupNotFoundException implements Exception {
  GroupNotFoundException(this.code);
  final String code;

  @override
  String toString() => '초대 코드 "$code"에 해당하는 그룹이 없습니다';
}

class GroupRepository {
  GroupRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 헷갈리는 0/O, 1/I 제외

  CollectionReference<Map<String, dynamic>> get _rooms => _firestore.collection('rooms');
  CollectionReference<Map<String, dynamic>> get _inviteCodes => _firestore.collection('inviteCodes');

  Future<String> createGroup({required String name, required String creatorUid}) async {
    final roomRef = _rooms.doc();
    final code = await _generateUniqueCode();

    await roomRef.set({
      'type': RoomType.group.toFirestore(),
      'name': name,
      'inviteCode': code,
      'participants': [creatorUid],
      'lastMessage': null,
      'lastMessageAt': null,
      'lastReadAt': <String, dynamic>{},
    });
    await _inviteCodes.doc(code).set({'roomId': roomRef.id});

    return roomRef.id;
  }

  Future<String> joinGroupByCode({required String code, required String uid}) async {
    final inviteDoc = await _inviteCodes.doc(code.toUpperCase()).get();
    if (!inviteDoc.exists) {
      throw GroupNotFoundException(code);
    }
    final roomId = inviteDoc.data()!['roomId'] as String;

    await _rooms.doc(roomId).update({
      'participants': FieldValue.arrayUnion([uid]),
    });

    return roomId;
  }

  Stream<List<ChatRoom>> myRoomsStream(String uid) {
    return _rooms
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs.map(ChatRoom.fromDoc).toList());
  }

  Future<void> markRead({required String roomId, required String uid}) {
    return _rooms.doc(roomId).update({
      'lastReadAt.$uid': Timestamp.now(),
    });
  }

  Future<String> _generateUniqueCode() async {
    final random = Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(6, (_) => _codeChars[random.nextInt(_codeChars.length)]).join();
      final exists = (await _inviteCodes.doc(code).get()).exists;
      if (!exists) return code;
    }
    throw StateError('초대 코드 생성에 반복적으로 실패했습니다');
  }
}
```

`markRead`는 Task 6에서 UI와 연결하지만, `lastReadAt` 갱신 경로가 방 생성/참여와 같은 파일에 있는 게 자연스러워 여기서 함께 구현한다.

- [ ] **Step 10: 테스트 통과 확인**

```bash
cd app && flutter test test/group/group_repository_test.dart
```

기대: 5개 테스트 모두 PASS.

- [ ] **Step 11: Riverpod provider 작성**

`app/lib/features/group/providers/group_providers.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../data/group_repository.dart';
import '../data/user_sync_service.dart';
import '../models/chat_room.dart';

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(firestoreProvider));
});

final userSyncServiceProvider = Provider<UserSyncService>((ref) {
  return UserSyncService(ref.watch(firestoreProvider));
});

final myRoomsProvider = StreamProvider<List<ChatRoom>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(groupRepositoryProvider).myRoomsStream(uid);
});
```

- [ ] **Step 12: 라우트 추가**

`app/lib/router.dart`에서 `AppRoutes` 클래스에 아래 상수와 메서드를 추가한다 (기존 `tabs`/`tabLabels`/`tabIcons`는 그대로 둔다).

```dart
  static const groupCreate = '/group/create';
  static const groupJoin = '/group/join';

  static String roomDetail(String roomId) => '/group/room/$roomId';
  static String roomLocationMap(String roomId) => '/group/room/$roomId/map';
```

`createRouter` 함수의 `routes` 리스트에서, `ShellRoute` 뒤에 아래 4개 라우트를 형제로 추가한다 (탭 바 없이 전체 화면으로 뜨게 하기 위해 `ShellRoute` 밖에 둔다).

```dart
      GoRoute(
        path: AppRoutes.groupCreate,
        builder: (_, __) => const CreateGroupPage(),
      ),
      GoRoute(
        path: AppRoutes.groupJoin,
        builder: (_, __) => const JoinGroupPage(),
      ),
      GoRoute(
        path: '/group/room/:roomId',
        builder: (_, state) => ChatRoomPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/group/room/:roomId/map',
        builder: (_, state) => GroupLocationMapPage(roomId: state.pathParameters['roomId']!),
      ),
```

파일 상단 import에 아래를 추가한다.

```dart
import 'features/group/screens/create_group_page.dart';
import 'features/group/screens/join_group_page.dart';
import 'features/group/screens/chat_room_page.dart';
import 'features/group/screens/group_location_map_page.dart';
```

`ChatRoomPage`, `GroupLocationMapPage`는 각각 Task 3, Task 8에서 만든다. 지금은 컴파일이 안 되는 게 정상이다 — 다음 스텝에서 최소 껍데기를 만들어 라우팅부터 통과시킨다.

- [ ] **Step 13: `ChatRoomPage`, `GroupLocationMapPage` 최소 껍데기, `CreateGroupPage`, `JoinGroupPage` 구현**

`app/lib/features/group/screens/create_group_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../providers/group_providers.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null || _controller.text.trim().isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(groupRepositoryProvider).createGroup(
            name: _controller.text.trim(),
            creatorUid: uid,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '그룹을 만들지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('그룹 만들기')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: '그룹 이름 (예: 오사카 여행)'),
            ),
            const SizedBox(height: 16),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('만들기'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`app/lib/features/group/screens/join_group_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../data/group_repository.dart';
import '../providers/group_providers.dart';

class JoinGroupPage extends ConsumerStatefulWidget {
  const JoinGroupPage({super.key});

  @override
  ConsumerState<JoinGroupPage> createState() => _JoinGroupPageState();
}

class _JoinGroupPageState extends ConsumerState<JoinGroupPage> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    final code = _controller.text.trim();
    if (uid == null || code.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(groupRepositoryProvider).joinGroupByCode(code: code, uid: uid);
      if (mounted) Navigator.of(context).pop();
    } on GroupNotFoundException {
      setState(() => _error = '해당 코드의 그룹을 찾을 수 없습니다');
    } catch (e) {
      setState(() => _error = '참여하지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('그룹 참여하기')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6자리 초대 코드'),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('참여하기'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`app/lib/features/group/screens/chat_room_page.dart` (지금은 최소 껍데기, Task 3에서 실제 채팅 UI로 채운다):

```dart
import 'package:flutter/material.dart';

class ChatRoomPage extends StatelessWidget {
  const ChatRoomPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('채팅방 $roomId')),
      body: const Center(child: Text('채팅')),
    );
  }
}
```

`app/lib/features/group/screens/group_location_map_page.dart` (최소 껍데기, Task 8에서 채운다):

```dart
import 'package:flutter/material.dart';

class GroupLocationMapPage extends StatelessWidget {
  const GroupLocationMapPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 위치')),
      body: const Center(child: Text('지도')),
    );
  }
}
```

`app/lib/features/group/screens/group_page.dart` 전체를 아래로 교체한다 (Phase 0 Task 7의 `Center(child: Text('그룹'))` 껍데기를 대체):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../router.dart';
import '../providers/group_providers.dart';
import '../widgets/unread_dot.dart';

class GroupPage extends ConsumerWidget {
  const GroupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final roomsAsync = ref.watch(myRoomsProvider);

    return Scaffold(
      body: roomsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('불러오지 못했습니다: $e')),
        data: (rooms) {
          if (rooms.isEmpty) {
            return const Center(child: Text('아직 참여한 그룹이 없습니다'));
          }
          return ListView.separated(
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final room = rooms[i];
              return ListTile(
                title: Text(room.name),
                subtitle: Text(room.lastMessage ?? '메시지 없음'),
                trailing: uid != null && room.hasUnreadFor(uid) ? const UnreadDot() : null,
                onTap: () => context.push(AppRoutesGroupNav.roomDetail(room.id)),
              );
            },
          );
        },
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'join',
            onPressed: () => context.push(AppRoutes.groupJoin),
            child: const Icon(Icons.qr_code),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'create',
            onPressed: () => context.push(AppRoutes.groupCreate),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
```

`context.push`를 쓰려면 `go_router`의 확장 메서드가 필요하므로 파일 상단에 `import 'package:go_router/go_router.dart';`를 추가한다. 위 코드의 `AppRoutesGroupNav.roomDetail`은 오타 방지용 별칭이 아니라 실수다 — `AppRoutes.roomDetail(room.id)`로 고쳐서 작성한다 (아래는 최종 정정본).

```dart
                onTap: () => context.push(AppRoutes.roomDetail(room.id)),
```

`app/lib/features/group/widgets/unread_dot.dart`:

```dart
import 'package:flutter/material.dart';

class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, shape: BoxShape.circle),
    );
  }
}
```

- [ ] **Step 14: `main.dart`에 유저 동기화 리스너 연결**

`app/lib/main.dart`의 `_Root` 위젯 `build` 메서드에서 `authState.when(...)`의 `data:` 분기 시작 부분에 아래 리스너를 추가한다 (Firebase 초기화 코드와 `TravelFootstepsApp` 반환 사이).

```dart
    ref.listen(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user != null) {
        ref.read(userSyncServiceProvider).syncProfile(user);
      }
    });
```

파일 상단 import에 `import 'features/group/providers/group_providers.dart';`를 추가한다.

- [ ] **Step 15: Android emulator에서 그룹 생성→참여 수동 확인**

로컬 Firestore 대신 실제 Firebase 프로젝트를 쓴다 (아직 Task 2의 보안 규칙이 없으므로 기본 규칙이 열려 있어야 동작한다 — Task 2에서 규칙을 잠근 뒤에도 이 플로우가 통과하는지 다시 확인한다).

```bash
cd app && flutter run
```

1. 그룹 탭 → `+` → 그룹 이름 입력 → 만들기 → 목록에 뜬다
2. Firebase 콘솔 Firestore에서 `rooms/{roomId}.inviteCode` 확인
3. 다른 계정(또는 같은 계정, 다른 uid로 테스트)으로 QR 아이콘 → 코드 입력 → 참여 → 같은 방이 목록에 뜬다

- [ ] **Step 16: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
```

기대: analyze 무경고, 전체 테스트 PASS.

```bash
git add app/lib/features/group app/lib/router.dart app/lib/main.dart app/test/group app/pubspec.yaml app/pubspec.lock
git commit -m "feat(app): Firestore 그룹 생성/참여와 유저 동기화"
```

---

### Task 2: Firestore 보안 규칙

**Files:**
- Create: `firebase.json`
- Create: `firestore.rules`
- Create: `firestore.indexes.json`

**Interfaces:**
- Consumes: Task 1의 컬렉션 구조 (`rooms`, `rooms/{roomId}/messages`, `inviteCodes`, `users`)
- Produces: 배포된 Firestore 보안 규칙. 이후 모든 Task의 실기기/에뮬레이터 수동 확인은 이 규칙 위에서 통과해야 한다.

> 스펙에 규칙 파일이 명시돼 있지 않지만, 그룹 멤버가 아닌 사용자가 채팅 내용을 읽을 수 있으면 안 되므로 반드시 필요하다. Firestore 콘솔의 시뮬레이터로 검증한다 (Flutter 단위 테스트로는 서버 측 규칙을 검증할 수 없다).

- [ ] **Step 1: Firebase CLI 초기화**

```bash
npm install -g firebase-tools   # 이미 있으면 생략
firebase login
firebase init firestore
```

프롬프트에서: 기존 Firebase 프로젝트(Phase 0에서 만든 `travel-footsteps`) 선택, `firestore.rules`/`firestore.indexes.json` 기본 경로 그대로 사용. 저장소 루트에서 실행해 `firebase.json`이 루트에 생기게 한다.

- [ ] **Step 2: 규칙 작성**

`firestore.rules`:

```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() {
      return request.auth != null;
    }

    function isParticipant(roomId) {
      return isSignedIn() &&
        request.auth.uid in get(/databases/$(database)/documents/rooms/$(roomId)).data.participants;
    }

    // users/{uid}: 채팅 UI가 상대방 displayName/photoUrl을 읽어야 하므로 로그인한 누구나 읽을 수 있다.
    // 자기 문서만 쓸 수 있다.
    match /users/{uid} {
      allow read: if isSignedIn();
      allow write: if isSignedIn() && request.auth.uid == uid;
    }

    // inviteCodes/{code}: 코드→roomId 매핑. 참여 플로우에서 비참가자도 "코드를 알고 있으면" 조회할 수
    // 있어야 하므로 단건 조회(get)는 열어두되, 컬렉션 전체 조회(list)는 반드시 막는다 — list까지 열면
    // 로그인한 아무나 전체 초대코드→roomId 매핑을 긁어와 초대 없이 모든 방을 알아낼 수 있다
    // (2026-09-12 리뷰에서 발견, Plan A Task 10의 "roomId는 초대코드로만 얻는 비공개 식별자"라는
    // 전제가 이 규칙에 의존한다).
    match /inviteCodes/{code} {
      allow get: if isSignedIn();
      allow list: if false;
      allow create: if isSignedIn() && !exists(/databases/$(database)/documents/inviteCodes/$(code));
      allow update, delete: if false;
    }

    match /rooms/{roomId} {
      allow read: if isParticipant(roomId);

      // 생성: 만드는 사람이 자기 자신을 참가자에 포함해야 한다.
      allow create: if isSignedIn() && request.auth.uid in request.resource.data.participants;

      // 참여: 기존 참가자 목록에 자기 uid 하나만 추가하는 요청만 허용한다.
      // 일반 갱신(메시지 미리보기, lastReadAt 등): 이미 참가자인 사람만.
      allow update: if isParticipant(roomId) ||
        (isSignedIn() &&
         request.resource.data.participants.size() == resource.data.participants.size() + 1 &&
         request.resource.data.participants.hasAll(resource.data.participants) &&
         request.auth.uid in request.resource.data.participants);

      allow delete: if false;

      match /messages/{messageId} {
        allow read: if isParticipant(roomId);
        allow create: if isParticipant(roomId) && request.resource.data.senderUid == request.auth.uid;
        allow update, delete: if false; // 메시지는 불변 — 읽음 표시는 rooms 문서의 lastReadAt만 바꾼다
      }
    }
  }
}
```

- [ ] **Step 3: 복합 인덱스 작성**

`firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "rooms",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "participants", "arrayConfig": "CONTAINS" },
        { "fieldPath": "lastMessageAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

`myRoomsStream`은 지금 `lastMessageAt` 정렬을 안 쓰지만, Task 3 이후 방 목록을 최신순으로 보여줄 때 이 인덱스가 필요해진다 — Firestore는 배포 후 인덱스 생성에 몇 분이 걸리므로 미리 만들어 둔다.

`firebase.json`은 `firebase init`이 만든 그대로 두되, `firestore` 섹션에 `rules`/`indexes` 경로가 잡혀 있는지 확인한다.

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  }
}
```

- [ ] **Step 4: Firebase 콘솔 규칙 시뮬레이터로 검증**

Firebase 콘솔 → Firestore Database → 규칙 → 시뮬레이터에서 아래 3가지를 확인한다.

1. 비참가자 uid로 `get /rooms/{roomId}` → **거부**
2. 참가자 uid로 `get /rooms/{roomId}` → **허용**
3. 참가자 uid로 `get /rooms/{roomId}/messages/{msgId}` → **허용**, 비참가자는 **거부**

- [ ] **Step 5: 배포**

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

- [ ] **Step 6: Task 1의 그룹 생성/참여 플로우가 규칙 아래서도 동작하는지 재확인**

```bash
cd app && flutter run
```

Task 1 Step 15와 같은 시나리오를 다시 실행한다. 실패하면 규칙의 `create`/`update` 조건과 `GroupRepository`가 실제로 보내는 필드가 일치하는지 대조한다 (특히 `create`에서 `request.resource.data.participants`가 배열인지).

- [ ] **Step 7: 커밋**

```bash
git add firebase.json firestore.rules firestore.indexes.json
git commit -m "feat: Firestore 보안 규칙 — 그룹 멤버만 채팅 읽기/쓰기"
```

---

### Task 3: 그룹 채팅 — 실시간 메시지 목록 + 텍스트 전송

**Files:**
- Create: `app/lib/features/group/data/chat_repository.dart`
- Create: `app/lib/features/group/providers/chat_providers.dart`
- Create: `app/lib/features/group/widgets/message_bubble.dart`
- Modify: `app/lib/features/group/screens/chat_room_page.dart`
- Test: `app/test/group/chat_repository_test.dart`

**Interfaces:**
- Consumes: Task 1의 `ChatRoom`, `ChatMessage`, `firestoreProvider`, `authStateProvider`
- Produces:
  - `ChatRepository` — `Stream<List<ChatMessage>> messagesStream(String roomId)` (오래된 순), `Future<void> sendText({required String roomId, required String senderUid, required String text})` — 메시지 생성과 동시에 방 문서의 `lastMessage`/`lastMessageAt`을 갱신한다 (batch write)
  - `chatRepositoryProvider`, `messagesProvider(String roomId)` (`StreamProvider.family<List<ChatMessage>, String>`)
  - Task 4(DM), Task 5(사진)가 `sendText`와 같은 배치 패턴(`sendImage`)으로 이어 짓는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/group/chat_repository_test.dart`:

```dart
import 'package:app/features/group/data/chat_repository.dart';
import 'package:app/features/group/models/chat_message.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ChatRepository repository;
  late String roomId;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = ChatRepository(firestore);
    final roomRef = await firestore.collection('rooms').add({
      'type': 'GROUP',
      'name': '테스트방',
      'participants': ['uid-1', 'uid-2'],
      'lastMessage': null,
      'lastMessageAt': null,
      'lastReadAt': <String, dynamic>{},
    });
    roomId = roomRef.id;
  });

  test('텍스트 메시지를 보내면 messages 서브컬렉션에 쌓인다', () async {
    await repository.sendText(roomId: roomId, senderUid: 'uid-1', text: '안녕');

    final messages = await repository.messagesStream(roomId).first;
    expect(messages, hasLength(1));
    expect(messages.first.text, '안녕');
    expect(messages.first.senderUid, 'uid-1');
    expect(messages.first.type, MessageType.text);
  });

  test('메시지를 보내면 방 문서의 lastMessage/lastMessageAt이 갱신된다', () async {
    await repository.sendText(roomId: roomId, senderUid: 'uid-1', text: '반가워');

    final room = await firestore.collection('rooms').doc(roomId).get();
    expect(room.data()!['lastMessage'], '반가워');
    expect(room.data()!['lastMessageAt'], isNotNull);
  });

  test('messagesStream은 오래된 순으로 정렬된다', () async {
    await repository.sendText(roomId: roomId, senderUid: 'uid-1', text: '첫번째');
    await repository.sendText(roomId: roomId, senderUid: 'uid-2', text: '두번째');

    final messages = await repository.messagesStream(roomId).first;

    expect(messages.map((m) => m.text), ['첫번째', '두번째']);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/group/chat_repository_test.dart
```

기대: 컴파일 실패 — `ChatRepository` 심볼을 찾을 수 없음.

- [ ] **Step 3: `ChatRepository` 구현**

`app/lib/features/group/data/chat_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';

class ChatRepository {
  ChatRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messages(String roomId) =>
      _firestore.collection('rooms').doc(roomId).collection('messages');

  Stream<List<ChatMessage>> messagesStream(String roomId) {
    return _messages(roomId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  Future<void> sendText({
    required String roomId,
    required String senderUid,
    required String text,
  }) async {
    final now = Timestamp.now();
    final batch = _firestore.batch();

    final msgRef = _messages(roomId).doc();
    batch.set(msgRef, {
      'senderUid': senderUid,
      'type': MessageType.text.toFirestore(),
      'text': text,
      'imageUrl': null,
      'lat': null,
      'lng': null,
      'createdAt': now,
    });

    final roomRef = _firestore.collection('rooms').doc(roomId);
    batch.update(roomRef, {
      'lastMessage': text,
      'lastMessageAt': now,
    });

    await batch.commit();
  }
}
```

메시지 생성 시각을 `FieldValue.serverTimestamp()`가 아니라 클라이언트 `Timestamp.now()`로 쓰는 이유는, 서버 타임스탬프는 `snapshots()` 스트림에서 로컬 캐시 단계에 `null`로 잠깐 보이는 특성이 있어 `orderBy('createdAt')` 쿼리·읽음 비교 로직을 다루기 더 복잡하게 만들기 때문이다. 팀 규모(4인, 같은 지역 시연)에서는 기기 시계 오차로 인한 순서 뒤바뀜 위험이 이 복잡성보다 작다.

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/group/chat_repository_test.dart
```

기대: 3개 테스트 모두 PASS.

- [ ] **Step 5: provider 작성**

`app/lib/features/group/providers/chat_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import 'group_providers.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(firestoreProvider));
});

final messagesProvider = StreamProvider.family<List<ChatMessage>, String>((ref, roomId) {
  return ref.watch(chatRepositoryProvider).messagesStream(roomId);
});
```

- [ ] **Step 6: 메시지 버블 위젯**

`app/lib/features/group/widgets/message_bubble.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final color = isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget content;
    switch (message.type) {
      case MessageType.text:
        content = Text(message.text ?? '');
      case MessageType.image:
        content = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(message.imageUrl!, width: 200, fit: BoxFit.cover),
        );
      case MessageType.location:
        content = Text('위치 공유: ${message.lat}, ${message.lng}');
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: content,
      ),
    );
  }
}
```

`MessageType.location`은 스펙 §7 스키마에 정의돼 있어 모델에 남겨 두지만, 이 계획서는 "위치 공유 메시지(1회성 핀)"를 보내는 UI를 만들지 않는다 — 지시받은 범위는 Task 8의 연속 실시간 공유뿐이다. 나중에 필요해지면 이 스위치 문에 이미 자리가 있다.

- [ ] **Step 7: `ChatRoomPage`를 실제 채팅 화면으로 교체**

`app/lib/features/group/screens/chat_room_page.dart` 전체를 아래로 교체한다.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../router.dart';
import '../providers/chat_providers.dart';
import '../widgets/message_bubble.dart';

class ChatRoomPage extends ConsumerStatefulWidget {
  const ChatRoomPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (text.isEmpty || uid == null) return;

    _textController.clear();
    await ref.read(chatRepositoryProvider).sendText(
          roomId: widget.roomId,
          senderUid: uid,
          text: text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final messagesAsync = ref.watch(messagesProvider(widget.roomId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on_outlined),
            tooltip: '실시간 위치',
            onPressed: () => context.push(AppRoutes.roomLocationMap(widget.roomId)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('메시지를 불러오지 못했습니다: $e')),
              data: (messages) => ListView.builder(
                controller: _scrollController,
                itemCount: messages.length,
                itemBuilder: (context, i) => MessageBubble(
                  message: messages[i],
                  isMine: messages[i].senderUid == uid,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(hintText: '메시지 입력'),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _sendText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

`context.push`를 쓰므로 파일 상단에 `import 'package:go_router/go_router.dart';`를 추가한다.

- [ ] **Step 8: 실기기 확인**

```bash
cd app && flutter run
```

그룹 방에 들어가 메시지를 보내고, 두 번째 기기(또는 에뮬레이터 2개)에서 실시간으로 도착하는지 확인한다.

- [ ] **Step 9: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/group app/test/group
git commit -m "feat(app): 그룹 채팅 실시간 메시지 목록과 텍스트 전송"
```

---

### Task 4: 1:1 DM

**Files:**
- Modify: `app/lib/features/group/data/group_repository.dart`
- Modify: `app/lib/features/group/screens/group_page.dart`
- Create: `app/lib/features/group/screens/start_dm_page.dart`
- Test: `app/test/group/group_repository_test.dart` (DM 케이스 추가)

**Interfaces:**
- Consumes: Task 1의 `GroupRepository`, `ChatRoom`, Task 3의 `ChatRoomPage`(재사용 — DM도 `rooms/{roomId}/messages`를 그대로 쓴다)
- Produces: `GroupRepository.startOrGetDm({required String myUid, required String otherUid})` → 기존 DM 방이 있으면 그 id, 없으면 새로 만든 id 반환. DM 방은 `type: DM`, `name`은 두 uid를 정렬해 합친 문자열(표시용이 아니라 중복 방지 키)로 저장하고, 화면에는 상대방의 `users/{uid}.displayName`을 조회해 보여준다.

- [ ] **Step 1: 실패하는 테스트 추가**

`app/test/group/group_repository_test.dart` 파일 끝(마지막 `test(...)` 뒤, `}` 앞)에 아래 3개 테스트를 추가한다.

```dart
  test('처음 DM을 시작하면 새 방을 만든다', () async {
    final roomId = await repository.startOrGetDm(myUid: 'uid-1', otherUid: 'uid-2');

    final room = await firestore.collection('rooms').doc(roomId).get();
    expect(room.data()!['type'], 'DM');
    expect(room.data()!['participants'], containsAll(['uid-1', 'uid-2']));
  });

  test('같은 두 사람이 다시 DM을 시작하면 기존 방을 재사용한다', () async {
    final first = await repository.startOrGetDm(myUid: 'uid-1', otherUid: 'uid-2');
    final second = await repository.startOrGetDm(myUid: 'uid-2', otherUid: 'uid-1');

    expect(second, first);
  });

  test('DM 방은 초대 코드로 참여할 수 없도록 inviteCode가 없다', () async {
    final roomId = await repository.startOrGetDm(myUid: 'uid-1', otherUid: 'uid-2');

    final room = await firestore.collection('rooms').doc(roomId).get();
    expect(room.data()!['inviteCode'], isNull);
  });
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/group/group_repository_test.dart
```

기대: 컴파일 실패 — `startOrGetDm` 메서드를 찾을 수 없음.

- [ ] **Step 3: `GroupRepository`에 `startOrGetDm` 추가**

`app/lib/features/group/data/group_repository.dart`의 `GroupRepository` 클래스 안, `joinGroupByCode` 메서드 뒤에 추가한다.

```dart
  /// 두 사용자 사이의 유일한 DM 키. 정렬해 합치므로 순서와 무관하게 같은 값이 나온다.
  String _dmKey(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return sorted.join('_');
  }

  Future<String> startOrGetDm({required String myUid, required String otherUid}) async {
    final dmKey = _dmKey(myUid, otherUid);
    final existing = await _rooms
        .where('type', isEqualTo: RoomType.dm.toFirestore())
        .where('dmKey', isEqualTo: dmKey)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final roomRef = _rooms.doc();
    await roomRef.set({
      'type': RoomType.dm.toFirestore(),
      'name': dmKey,
      'dmKey': dmKey,
      'inviteCode': null,
      'participants': [myUid, otherUid],
      'lastMessage': null,
      'lastMessageAt': null,
      'lastReadAt': <String, dynamic>{},
    });
    return roomRef.id;
  }
```

`createGroup`이 쓰는 `_rooms` getter를 그대로 재사용한다.

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/group/group_repository_test.dart
```

기대: 전체(기존 5개 + 신규 3개) PASS.

- [ ] **Step 5: DM 시작 화면**

`app/lib/features/group/screens/start_dm_page.dart` — 그룹 멤버 목록에서 한 명을 골라 DM을 시작한다. 그룹 참가자의 uid 목록은 `ChatRoom.participants`에서 오고, 표시 이름은 `users/{uid}`를 조회한다.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../router.dart';
import '../providers/group_providers.dart';

class StartDmPage extends ConsumerWidget {
  const StartDmPage({super.key, required this.groupRoomId, required this.participantUids});

  final String groupRoomId;
  final List<String> participantUids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(authStateProvider).valueOrNull?.uid;
    final others = participantUids.where((uid) => uid != myUid).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('DM 시작')),
      body: ListView.builder(
        itemCount: others.length,
        itemBuilder: (context, i) {
          final otherUid = others[i];
          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: ref.read(firestoreProvider).collection('users').doc(otherUid).get(),
            builder: (context, snapshot) {
              final name = snapshot.data?.data()?['displayName'] as String? ?? otherUid;
              return ListTile(
                title: Text(name),
                onTap: () async {
                  if (myUid == null) return;
                  final roomId = await ref
                      .read(groupRepositoryProvider)
                      .startOrGetDm(myUid: myUid, otherUid: otherUid);
                  if (context.mounted) {
                    context.push(AppRoutes.roomDetail(roomId));
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: 그룹 상세에서 DM 시작 화면으로 이동하는 경로 추가**

`app/lib/router.dart`에 라우트를 추가한다. `AppRoutes`에:

```dart
  static const groupMembersPrefix = '/group/room';
  static String startDm(String groupRoomId) => '/group/room/$groupRoomId/dm';
```

`routes` 리스트에 `GoRoute(path: '/group/room/:roomId/map', ...)` 다음에 추가한다.

```dart
      GoRoute(
        path: '/group/room/:roomId/dm',
        builder: (_, state) {
          final roomId = state.pathParameters['roomId']!;
          final uids = (state.extra as List<String>?) ?? const <String>[];
          return StartDmPage(groupRoomId: roomId, participantUids: uids);
        },
      ),
```

import 추가:

```dart
import 'features/group/screens/start_dm_page.dart';
```

- [ ] **Step 7: `ChatRoomPage` 그룹 채팅방 AppBar에 "멤버 목록/DM 시작" 진입점 추가**

`app/lib/features/group/screens/chat_room_page.dart`의 `AppBar.actions`에 아래를 `location_on_outlined` 버튼 앞에 추가한다. 방 참가자 목록이 필요하므로 `roomProvider`(단건 방 조회)가 없다면 `myRoomsProvider`에서 현재 방을 찾아 쓴다.

```dart
          IconButton(
            icon: const Icon(Icons.person_add_alt_outlined),
            tooltip: 'DM 시작',
            onPressed: () {
              final rooms = ref.read(myRoomsProvider).valueOrNull ?? [];
              final room = rooms.where((r) => r.id == widget.roomId).firstOrNull;
              if (room == null) return;
              context.push('/group/room/${widget.roomId}/dm', extra: room.participants);
            },
          ),
```

`import '../providers/group_providers.dart';`를 파일 상단에 추가한다. `firstOrNull`은 `package:collection`이 필요하면 대신 아래처럼 수동으로 찾는다.

```dart
              ChatRoom? room;
              for (final r in rooms) {
                if (r.id == widget.roomId) { room = r; break; }
              }
              if (room == null) return;
```

(둘 중 하나만 채택 — `collection` 패키지가 이미 의존성에 있으면 `firstOrNull`을, 없으면 수동 루프를 쓴다.)

- [ ] **Step 8: 실기기 확인**

그룹 채팅방 → DM 시작 → 멤버 선택 → DM 방 생성 → 메시지 주고받기까지 확인한다. DM 방은 그룹 탭 목록에도 그대로 나타난다 (`myRoomsStream`이 `type` 구분 없이 `participants`만 본다).

- [ ] **Step 9: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/group app/lib/router.dart app/test/group
git commit -m "feat(app): 1:1 DM 시작과 재사용"
```

---

### Task 5: 사진 전송 (Firebase Storage)

**Files:**
- Create: `app/lib/features/group/data/image_uploader.dart`
- Modify: `app/lib/features/group/data/chat_repository.dart`
- Modify: `app/lib/features/group/providers/chat_providers.dart`
- Modify: `app/lib/features/group/screens/chat_room_page.dart`
- Test: `app/test/group/image_uploader_test.dart`
- Test: `app/test/group/chat_repository_test.dart` (사진 케이스 추가)

**Interfaces:**
- Consumes: Task 3의 `ChatRepository`, `ChatMessage`
- Produces: `abstract class ImageUploader { Future<String> upload({required String roomId, required File file}); }`, `FirebaseStorageImageUploader`(실제 구현), `FakeImageUploader`(테스트용), `ChatRepository.sendImage({required String roomId, required String senderUid, required String downloadUrl})`

- [ ] **Step 1: 인터페이스와 Fake, 실제 구현 작성**

`app/lib/features/group/data/image_uploader.dart`:

```dart
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

abstract class ImageUploader {
  Future<String> upload({required String roomId, required File file});
}

class FirebaseStorageImageUploader implements ImageUploader {
  FirebaseStorageImageUploader([FirebaseStorage? storage]) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<String> upload({required String roomId, required File file}) async {
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.jpg';
    final ref = _storage.ref('chat_images/$roomId/$fileName');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}

/// 테스트용 — 실제 업로드 없이 고정 URL을 돌려준다.
class FakeImageUploader implements ImageUploader {
  FakeImageUploader({this.urlToReturn = 'https://fake.storage/test.jpg'});

  final String urlToReturn;
  final List<String> uploadedRoomIds = [];

  @override
  Future<String> upload({required String roomId, required File file}) async {
    uploadedRoomIds.add(roomId);
    return urlToReturn;
  }
}
```

- [ ] **Step 2: `FakeImageUploader` 자체 검증 테스트**

`app/test/group/image_uploader_test.dart`:

```dart
import 'dart:io';

import 'package:app/features/group/data/image_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeImageUploader는 고정 URL을 반환하고 호출을 기록한다', () async {
    final uploader = FakeImageUploader(urlToReturn: 'https://fake.storage/pic.jpg');

    final url = await uploader.upload(roomId: 'room-1', file: File('dummy.jpg'));

    expect(url, 'https://fake.storage/pic.jpg');
    expect(uploader.uploadedRoomIds, ['room-1']);
  });
}
```

```bash
cd app && flutter test test/group/image_uploader_test.dart
```

기대: PASS (구현과 동시에 작성했으므로 바로 통과 — 이 클래스는 테스트 대역 자체가 산출물이다).

- [ ] **Step 3: `ChatRepository.sendImage` 실패하는 테스트 작성**

`app/test/group/chat_repository_test.dart` 마지막 테스트 뒤에 추가한다.

```dart
  test('사진 메시지를 보내면 imageUrl이 저장되고 lastMessage는 안내 문구다', () async {
    await repository.sendImage(roomId: roomId, senderUid: 'uid-1', downloadUrl: 'https://x/y.jpg');

    final messages = await repository.messagesStream(roomId).first;
    expect(messages.first.type, MessageType.image);
    expect(messages.first.imageUrl, 'https://x/y.jpg');

    final room = await firestore.collection('rooms').doc(roomId).get();
    expect(room.data()!['lastMessage'], '사진');
  });
```

- [ ] **Step 4: 테스트 실패 확인**

```bash
cd app && flutter test test/group/chat_repository_test.dart
```

기대: 컴파일 실패 — `sendImage` 메서드를 찾을 수 없음.

- [ ] **Step 5: `ChatRepository.sendImage` 구현**

`app/lib/features/group/data/chat_repository.dart`의 `sendText` 메서드 뒤에 추가한다.

```dart
  Future<void> sendImage({
    required String roomId,
    required String senderUid,
    required String downloadUrl,
  }) async {
    final now = Timestamp.now();
    final batch = _firestore.batch();

    final msgRef = _messages(roomId).doc();
    batch.set(msgRef, {
      'senderUid': senderUid,
      'type': MessageType.image.toFirestore(),
      'text': null,
      'imageUrl': downloadUrl,
      'lat': null,
      'lng': null,
      'createdAt': now,
    });

    final roomRef = _firestore.collection('rooms').doc(roomId);
    batch.update(roomRef, {
      'lastMessage': '사진',
      'lastMessageAt': now,
    });

    await batch.commit();
  }
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
cd app && flutter test test/group/chat_repository_test.dart
```

기대: 전체(기존 3개 + 신규 1개) PASS.

- [ ] **Step 7: provider에 업로더 추가**

`app/lib/features/group/providers/chat_providers.dart`에 추가한다.

```dart
import '../data/image_uploader.dart';

final imageUploaderProvider = Provider<ImageUploader>((ref) => FirebaseStorageImageUploader());
```

- [ ] **Step 8: `ChatRoomPage`에 사진 첨부 버튼 추가**

`app/lib/features/group/screens/chat_room_page.dart`의 `_ChatRoomPageState`에 메서드를 추가하고, 입력줄에 버튼을 하나 더 둔다.

```dart
  Future<void> _sendImage() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final uploader = ref.read(imageUploaderProvider);
    final url = await uploader.upload(roomId: widget.roomId, file: File(picked.path));
    await ref.read(chatRepositoryProvider).sendImage(
          roomId: widget.roomId,
          senderUid: uid,
          downloadUrl: url,
        );
  }
```

`Row(children: [...])`의 `TextField` 앞에 버튼을 추가한다.

```dart
                  IconButton(icon: const Icon(Icons.image_outlined), onPressed: _sendImage),
```

파일 상단 import에 추가한다.

```dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
```

- [ ] **Step 9: Android 권한 설정**

`app/android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 안(`<application>` 위)에 없으면 추가한다.

```xml
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

- [ ] **Step 10: 실기기 확인**

```bash
cd app && flutter run
```

채팅방에서 사진 아이콘 → 갤러리에서 사진 선택 → 전송 → 버블에 이미지가 뜨는지, Firebase Storage 콘솔 `chat_images/{roomId}/` 아래 파일이 올라갔는지 확인한다.

- [ ] **Step 11: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/group app/test/group app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(app): Firebase Storage 사진 전송"
```

---

### Task 6: 읽음 표시

**Files:**
- Modify: `app/lib/features/group/screens/chat_room_page.dart`
- Modify: `app/lib/features/group/screens/group_page.dart` (이미 Task 1에서 `UnreadDot` 연결됨 — 갱신 트리거만 추가)
- Test: `app/test/group/group_repository_test.dart` (markRead 케이스 추가)

**Interfaces:**
- Consumes: Task 1의 `GroupRepository.markRead`, `ChatRoom.hasUnreadFor`(Task 1에서 이미 구현·테스트됨)
- Produces: 채팅방에 진입/새 메시지 수신 시 `markRead` 호출. 그룹 목록 화면의 `UnreadDot`이 실시간으로 사라진다.

> 이 태스크의 핵심 로직(`hasUnreadFor`)은 이미 Task 1 Step 2에서 TDD로 구현·검증했다. 여기서는 "메시지 단위로 안 쓴다"는 제약을 지키는 갱신 지점(`markRead` 호출 시점)만 남았다 — `GroupRepository.markRead`도 Task 1 Step 9에서 이미 구현되어 있으므로, 이 태스크는 그 호출부만 테스트-우선으로 채운다.

- [ ] **Step 1: `markRead` 실패하는 테스트 추가**

`app/test/group/group_repository_test.dart` 마지막 테스트 뒤에 추가한다.

```dart
  test('markRead는 해당 유저의 lastReadAt만 갱신하고 다른 유저는 건드리지 않는다', () async {
    final roomId = await repository.createGroup(name: '읽음테스트', creatorUid: 'uid-1');
    await repository.joinGroupByCode(
      code: (await firestore.collection('rooms').doc(roomId).get()).data()!['inviteCode'] as String,
      uid: 'uid-2',
    );
    await repository.markRead(roomId: roomId, uid: 'uid-2');

    final room = await firestore.collection('rooms').doc(roomId).get();
    final lastReadAt = room.data()!['lastReadAt'] as Map<String, dynamic>;
    expect(lastReadAt.containsKey('uid-2'), isTrue);
    expect(lastReadAt.containsKey('uid-1'), isFalse);
  });
```

- [ ] **Step 2: 테스트 실행 — 이미 통과해야 정상**

```bash
cd app && flutter test test/group/group_repository_test.dart
```

기대: 전체 PASS (구현은 Task 1에서 이미 끝났음을 재확인하는 회귀 테스트). 만약 실패한다면 Task 1의 `markRead` 구현이 `lastReadAt.$uid` 점(dot) 표기 업데이트를 쓰지 않고 맵 전체를 덮어쓰는 등의 실수가 있는 것이므로, `app/lib/features/group/data/group_repository.dart`의 `markRead`를 아래와 동일한지 대조한다.

```dart
  Future<void> markRead({required String roomId, required String uid}) {
    return _rooms.doc(roomId).update({
      'lastReadAt.$uid': Timestamp.now(),
    });
  }
```

- [ ] **Step 3: `ChatRoomPage`에서 진입 시 + 새 메시지 수신 시 읽음 처리**

`app/lib/features/group/screens/chat_room_page.dart`의 `_ChatRoomPageState`에 아래를 추가한다.

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    await ref.read(groupRepositoryProvider).markRead(roomId: widget.roomId, uid: uid);
  }
```

`build` 메서드의 `messagesAsync.when(... data: (messages) => ...)` 블록 시작 부분에서, 메시지 개수가 바뀔 때마다 다시 읽음 처리하도록 `ref.listen`을 `build` 위쪽에 추가한다.

```dart
    ref.listen(messagesProvider(widget.roomId), (previous, next) {
      final prevLen = previous?.valueOrNull?.length ?? -1;
      final nextLen = next.valueOrNull?.length ?? -1;
      if (nextLen > prevLen) _markRead();
    });
```

파일 상단 import에 `import '../providers/group_providers.dart';`를 추가한다 (Task 4에서 이미 추가했다면 중복 추가하지 않는다).

- [ ] **Step 4: 실기기 확인**

기기 A에서 메시지 전송 → 기기 B가 채팅방을 보고 있지 않을 때는 그룹 목록에 빨간 점이 뜨고, 채팅방에 들어가면 즉시 사라지는지 확인한다.

- [ ] **Step 5: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/group app/test/group
git commit -m "feat(app): 읽음 표시 — lastReadAt 갱신과 안읽음 점 표시"
```

---

### Task 7: FCM 푸시 알림

**Files:**
- Create: `functions/package.json`
- Create: `functions/tsconfig.json`
- Create: `functions/src/index.ts`
- Modify: `app/lib/features/group/data/user_sync_service.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/group/user_sync_service_test.dart` (fcmToken 케이스 추가)

**Interfaces:**
- Consumes: Task 1의 `UserSyncService`, `users/{uid}` 문서, Task 3의 `rooms/{roomId}/messages/{msgId}` 생성 이벤트
- Produces: `UserSyncService.syncFcmToken(String uid, String token)`. 새 메시지가 생성되면 Cloud Function이 발신자를 제외한 참가자에게 FCM을 보낸다. 앱은 포그라운드 수신 시 로컬 알림으로 띄운다.

> 이 기능은 Flutter 코드만으로 끝나지 않는다 — "새 메시지 도착 시" 자동으로 트리거되려면 서버 쪽 어딘가에 Firestore 이벤트를 구독하는 코드가 있어야 한다. 스펙에는 이 트리거의 소유자가 명시돼 있지 않다(Spring 서버는 REST/WebSocket만 다루고 Firestore를 구독하지 않는다). Firestore와 가장 자연스럽게 통합되는 **Firebase Cloud Functions(2세대, Node.js)** 로 구현한다. Spring 서버 코드는 건드리지 않는다.

- [ ] **Step 1: `UserSyncService.syncFcmToken` 실패하는 테스트 추가**

`app/test/group/user_sync_service_test.dart` 마지막 테스트 뒤에 추가한다.

```dart
  test('syncFcmToken은 fcmToken 필드만 갱신하고 displayName은 건드리지 않는다', () async {
    await firestore.collection('users').doc('uid-4').set({'displayName': '기존이름'});

    await service.syncFcmToken('uid-4', 'token-xyz');

    final doc = await firestore.collection('users').doc('uid-4').get();
    expect(doc.data()!['fcmToken'], 'token-xyz');
    expect(doc.data()!['displayName'], '기존이름');
  });
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd app && flutter test test/group/user_sync_service_test.dart
```

기대: 컴파일 실패 — `syncFcmToken` 메서드를 찾을 수 없음.

- [ ] **Step 3: `UserSyncService`에 메서드 추가**

`app/lib/features/group/data/user_sync_service.dart`의 `syncProfile` 뒤에 추가한다.

```dart
  Future<void> syncFcmToken(String uid, String token) {
    return _firestore.collection('users').doc(uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
cd app && flutter test test/group/user_sync_service_test.dart
```

기대: 전체(기존 3개 + 신규 1개) PASS.

- [ ] **Step 5: `main.dart`에 FCM 초기화·토큰 등록·포그라운드 알림 연결**

`app/lib/main.dart` 전체를 아래로 교체한다.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth_providers.dart';
import 'features/group/providers/group_providers.dart';
import 'router.dart';

final _localNotifications = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드에서는 시스템이 알림을 자동으로 띄운다 (notification 페이로드 사용).
  // 여기서는 아무 것도 하지 않아도 된다 — 커스텀 처리(뱃지 등)가 필요해지면 이 자리에 추가한다.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  FirebaseMessaging.onMessage.listen((message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          '채팅 메시지',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  });

  runApp(const ProviderScope(child: _Root()));
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    ref.listen(authStateProvider, (previous, next) async {
      final user = next.valueOrNull;
      if (user == null) return;
      await ref.read(userSyncServiceProvider).syncProfile(user);

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ref.read(userSyncServiceProvider).syncFcmToken(user.uid, token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        ref.read(userSyncServiceProvider).syncFcmToken(user.uid, newToken);
      });
    });

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

- [ ] **Step 6: Android 알림 권한(Android 13+)**

`app/android/app/src/main/AndroidManifest.xml`의 `<manifest>` 태그 안에 추가한다 (없으면).

```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Android 13(API 33) 이상은 런타임 권한 요청이 필요하다. `firebase_messaging`은 `FirebaseMessaging.instance.requestPermission()`을 호출해야 팝업이 뜬다 — `_Root`의 `ref.listen` 콜백 안, 토큰을 가져오기 전에 추가한다.

```dart
      await FirebaseMessaging.instance.requestPermission();
```

- [ ] **Step 7: Cloud Functions 프로젝트 초기화**

```bash
firebase init functions
```

프롬프트: 언어 **TypeScript**, ESLint 사용 여부는 팀 선택. 기존 `firebase.json`(Task 2에서 만든)에 `functions` 섹션이 추가된다.

- [ ] **Step 8: 새 메시지 → FCM 트리거 작성**

`functions/src/index.ts`:

```typescript
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

initializeApp();

export const onNewChatMessage = onDocumentCreated(
  "rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const message = snapshot.data();
    const { roomId } = event.params;
    const db = getFirestore();

    const roomDoc = await db.collection("rooms").doc(roomId).get();
    const room = roomDoc.data();
    if (!room) return;

    const senderUid: string = message.senderUid;
    const recipientUids: string[] = (room.participants ?? []).filter(
      (uid: string) => uid !== senderUid
    );
    if (recipientUids.length === 0) return;

    const usersSnap = await db.getAll(
      ...recipientUids.map((uid) => db.collection("users").doc(uid))
    );
    const tokens = usersSnap
      .map((doc) => doc.data()?.fcmToken as string | undefined)
      .filter((token): token is string => !!token);
    if (tokens.length === 0) return;

    const senderDoc = await db.collection("users").doc(senderUid).get();
    const senderName = (senderDoc.data()?.displayName as string) ?? "여행자";

    const body =
      message.type === "IMAGE"
        ? "사진을 보냈습니다"
        : message.type === "LOCATION"
        ? "위치를 공유했습니다"
        : (message.text as string) ?? "";

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: room.type === "GROUP" ? `${room.name} · ${senderName}` : senderName,
        body,
      },
      data: { roomId },
    });
  }
);
```

`functions/package.json`, `functions/tsconfig.json`은 `firebase init functions`가 생성한 기본값을 그대로 쓴다 (Node 18+ 런타임, `firebase-admin`/`firebase-functions` 최신 버전이 자동으로 들어간다).

- [ ] **Step 9: 로컬 에뮬레이터로 트리거 확인**

```bash
cd functions && npm install
firebase emulators:start --only functions,firestore
```

다른 터미널에서 에뮬레이터의 Firestore에 직접 메시지 문서를 추가해 함수 로그에 `sendEachForMulticast` 성공이 찍히는지 확인한다. (에뮬레이터는 실제 FCM을 보내지 않고 호출만 검증한다.)

- [ ] **Step 10: 배포**

```bash
firebase deploy --only functions
```

- [ ] **Step 11: 실기기 종단 확인**

기기 A에서 로그인 → 토큰이 `users/{uid}.fcmToken`에 저장됐는지 Firebase 콘솔에서 확인 → 기기 B가 앱을 백그라운드로 보낸 상태에서 기기 A가 메시지 전송 → 기기 B에 시스템 알림이 뜨는지 확인. 포그라운드 상태에서는 `_localNotifications.show`로 뜨는 커스텀 알림을 확인한다.

- [ ] **Step 12: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
```

```bash
git add app/lib/main.dart app/lib/features/group/data/user_sync_service.dart app/test/group functions firebase.json app/android/app/src/main/AndroidManifest.xml
git commit -m "feat: FCM 푸시 알림 — 클라이언트 등록 + 새 메시지 Cloud Function 트리거"
```

---

### Task 8: 실시간 위치공유

**Files:**
- Create: `app/lib/features/group/data/location_share_client.dart`
- Create: `app/lib/features/group/controllers/location_share_controller.dart`
- Create: `app/lib/features/group/providers/location_share_providers.dart`
- Modify: `app/lib/features/group/screens/group_location_map_page.dart`
- Test: `app/test/group/location_share_client_test.dart`
- Test: `app/test/group/location_share_controller_test.dart`

**Interfaces:**
- Consumes: Task 1의 `AppRoutes.roomLocationMap`, Phase 0의 `authStateProvider.currentIdToken()`을 대신하는 `AuthRepository.currentIdToken()`, 스펙 §7의 STOMP 계약 (`SEND /app/location {roomId, lat, lng, ts}`, `SUBSCRIBE /topic/group/{roomId}/location`), Task 9(Phase 0)의 `resolveBaseUrl`
- Produces:
  - `abstract class LocationShareClient { Future<void> connect(String idToken); void sendLocation({required String roomId, required double lat, required double lng}); Stream<GroupLocationUpdate> subscribeToGroup(String roomId); Future<void> disconnect(); }`
  - `GroupLocationUpdate` — `{uid, lat, lng, ts}` (서버가 보내는 페이로드에 발신자 uid가 없다면 STOMP 헤더 대신 페이로드에 `uid`를 함께 보내도록 Plan A와 맞춘다 — 이 계획서는 페이로드에 `uid` 필드가 있다고 가정하고 없으면 무시한다)
  - `StompLocationShareClient`(실제 구현), `FakeLocationShareClient`(테스트용)
  - `LocationShareController` — 5초 틱(주입 가능한 `Stream<void>`)마다 현재 위치를 얻어 전송하고, 앱이 백그라운드로 가면 즉시 멈춘다
  - `locationSharingEnabledProvider` (`StateProvider<bool>`, 기본 `false`), `groupLocationsProvider(String roomId)` (`StreamProvider.family<Map<String, LatLng>, String>`)

> **Plan C 재사용 지점**: 지도를 그리는 부분(`GoogleMap` 위젯 자체)은 Plan C가 이미 발걸음 지도용으로 만든 공용 지도 위젯이 있다면 그것을 쓴다. 예를 들어 Plan C가 `app/lib/core/widgets/travel_map_view.dart`에 `TravelMapView({required List<Marker> markers, required LatLng initialCenter})` 같은 위젯을 노출한다면, Step 6의 `GroupLocationMapPage` 본문을 그 위젯으로 교체하고 `markers`만 이 화면의 위치 스트림에서 만들어 넘기면 된다. **그런 공용 위젯이 아직 없거나 시그니처가 다르면**, 아래 Step 6의 자체 `GoogleMap` 구현을 그대로 쓴다 — 이 계획서는 Plan C 완료를 기다리지 않고도 동작하도록 작성했다.

- [ ] **Step 1: `LocationShareClient` 인터페이스와 Fake 작성**

`app/lib/features/group/data/location_share_client.dart`:

```dart
class GroupLocationUpdate {
  const GroupLocationUpdate({required this.uid, required this.lat, required this.lng, required this.ts});

  final String uid;
  final double lat;
  final double lng;
  final int ts;
}

abstract class LocationShareClient {
  Future<void> connect(String idToken);

  void sendLocation({required String roomId, required double lat, required double lng});

  Stream<GroupLocationUpdate> subscribeToGroup(String roomId);

  Future<void> disconnect();
}

/// 테스트/개발용 — 실제 서버 없이 send를 기록하고 수동으로 이벤트를 흘려보낼 수 있다.
class FakeLocationShareClient implements LocationShareClient {
  final List<Map<String, dynamic>> sentPayloads = [];
  bool connected = false;
  final _controllers = <String, StreamController<GroupLocationUpdate>>{};

  @override
  Future<void> connect(String idToken) async {
    connected = true;
  }

  @override
  void sendLocation({required String roomId, required double lat, required double lng}) {
    sentPayloads.add({'roomId': roomId, 'lat': lat, 'lng': lng});
  }

  @override
  Stream<GroupLocationUpdate> subscribeToGroup(String roomId) {
    return _controllers.putIfAbsent(roomId, () => StreamController.broadcast()).stream;
  }

  void emit(String roomId, GroupLocationUpdate update) {
    _controllers[roomId]?.add(update);
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}
```

파일 상단에 `import 'dart:async';`를 추가한다.

- [ ] **Step 2: `FakeLocationShareClient` 검증 테스트**

`app/test/group/location_share_client_test.dart`:

```dart
import 'package:app/features/group/data/location_share_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connect 전에는 connected가 false, connect 후에는 true', () async {
    final client = FakeLocationShareClient();
    expect(client.connected, isFalse);

    await client.connect('token');

    expect(client.connected, isTrue);
  });

  test('sendLocation은 페이로드를 기록한다', () async {
    final client = FakeLocationShareClient();

    client.sendLocation(roomId: 'r1', lat: 37.5, lng: 127.0);

    expect(client.sentPayloads, [
      {'roomId': 'r1', 'lat': 37.5, 'lng': 127.0},
    ]);
  });

  test('emit으로 흘려보낸 이벤트를 subscribeToGroup으로 받는다', () async {
    final client = FakeLocationShareClient();
    final events = <GroupLocationUpdate>[];
    final sub = client.subscribeToGroup('r1').listen(events.add);

    client.emit('r1', const GroupLocationUpdate(uid: 'uid-2', lat: 1, lng: 2, ts: 1000));
    await Future.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.first.uid, 'uid-2');
    await sub.cancel();
  });
}
```

```bash
cd app && flutter test test/group/location_share_client_test.dart
```

기대: 3개 테스트 모두 PASS (Fake와 동시에 구현했으므로 실패 단계 없음 — 이 클래스 자체가 테스트 대역이라 인터페이스 정의가 곧 구현이다).

- [ ] **Step 3: 실제 STOMP 구현체 작성 (수동 검증만, 서버가 필요하므로 단위 테스트 대상 아님)**

`app/lib/features/group/data/location_share_client.dart` 파일 끝에 추가한다.

```dart
class StompLocationShareClient implements LocationShareClient {
  StompLocationShareClient({required this.wsUrl});

  final String wsUrl;
  StompClient? _client;
  final _controllers = <String, StreamController<GroupLocationUpdate>>{};

  @override
  Future<void> connect(String idToken) async {
    final completer = Completer<void>();
    _client = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $idToken'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $idToken'},
        onConnect: (frame) => completer.complete(),
        onWebSocketError: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      ),
    );
    _client!.activate();
    return completer.future;
  }

  @override
  void sendLocation({required String roomId, required double lat, required double lng}) {
    _client?.send(
      destination: '/app/location',
      body: jsonEncode({
        'roomId': roomId,
        'lat': lat,
        'lng': lng,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  @override
  Stream<GroupLocationUpdate> subscribeToGroup(String roomId) {
    final controller = _controllers.putIfAbsent(roomId, () => StreamController.broadcast());
    _client?.subscribe(
      destination: '/topic/group/$roomId/location',
      callback: (frame) {
        if (frame.body == null) return;
        final data = jsonDecode(frame.body!) as Map<String, dynamic>;
        final uid = data['uid'] as String?;
        if (uid == null) return; // 서버가 발신자 uid를 안 넣으면 그룹원 구분이 불가능하므로 무시
        controller.add(GroupLocationUpdate(
          uid: uid,
          lat: (data['lat'] as num).toDouble(),
          lng: (data['lng'] as num).toDouble(),
          ts: data['ts'] as int,
        ));
      },
    );
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    await _client?.deactivate();
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}

String resolveWsUrl({required bool isAndroid}) =>
    isAndroid ? 'ws://10.0.2.2:8080/ws' : 'ws://localhost:8080/ws';
```

파일 상단 import를 아래로 갱신한다.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';
```

> **서버 계약 확인 필요**: 위 코드는 서버가 위치 브로드캐스트 페이로드에 `uid` 필드를 포함해 보낸다고 가정한다. 스펙 §7에는 `SEND /app/location {roomId, lat, lng, ts}`만 있고 브로드캐스트 페이로드 형식은 명시돼 있지 않다 — Plan A(R1) 구현 시 서버가 수신자에게 발신자 uid를 포함해 릴레이하는지 반드시 맞춰야 한다. 안 맞으면 `subscribeToGroup`의 `uid == null` 분기에서 모든 이벤트가 조용히 버려진다.

- [ ] **Step 4: `LocationShareController` 실패하는 테스트 작성**

포그라운드에서만, 5초 틱마다 전송하는 로직을 실제 `Timer`가 아니라 주입된 `Stream<void>`로 제어해 테스트 결정성을 확보한다.

`app/test/group/location_share_controller_test.dart`:

```dart
import 'dart:async';

import 'package:app/features/group/controllers/location_share_controller.dart';
import 'package:app/features/group/data/location_share_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedPositionProvider {
  int calls = 0;
  Future<({double lat, double lng})> current() async {
    calls++;
    return (lat: 37.0 + calls, lng: 127.0 + calls);
  }
}

void main() {
  late FakeLocationShareClient client;
  late _FixedPositionProvider position;
  late StreamController<void> ticks;
  late LocationShareController controller;

  setUp(() {
    client = FakeLocationShareClient();
    position = _FixedPositionProvider();
    ticks = StreamController<void>.broadcast();
    controller = LocationShareController(
      client: client,
      tickStream: ticks.stream,
      currentPosition: position.current,
    );
  });

  tearDown(() => ticks.close());

  test('start 후 연결하고, 틱마다 위치를 전송한다', () async {
    await controller.start(roomId: 'room-1', idToken: 'token');

    ticks.add(null);
    await Future.delayed(Duration.zero);
    ticks.add(null);
    await Future.delayed(Duration.zero);

    expect(client.connected, isTrue);
    expect(client.sentPayloads, hasLength(2));
    expect(client.sentPayloads[0]['roomId'], 'room-1');
  });

  test('stop 이후에는 틱이 와도 전송하지 않는다', () async {
    await controller.start(roomId: 'room-1', idToken: 'token');
    await controller.stop();

    ticks.add(null);
    await Future.delayed(Duration.zero);

    expect(client.sentPayloads, isEmpty);
    expect(client.connected, isFalse);
  });

  test('앱이 백그라운드로 가면 틱이 와도 전송하지 않는다', () async {
    await controller.start(roomId: 'room-1', idToken: 'token');

    controller.onAppLifecycleChanged(AppLifecycleState.paused);
    ticks.add(null);
    await Future.delayed(Duration.zero);

    expect(client.sentPayloads, isEmpty);
  });

  test('백그라운드에서 포그라운드로 돌아오면 다시 전송한다', () async {
    await controller.start(roomId: 'room-1', idToken: 'token');
    controller.onAppLifecycleChanged(AppLifecycleState.paused);
    controller.onAppLifecycleChanged(AppLifecycleState.resumed);

    ticks.add(null);
    await Future.delayed(Duration.zero);

    expect(client.sentPayloads, hasLength(1));
  });
}
```

- [ ] **Step 5: 테스트 실패 확인**

```bash
cd app && flutter test test/group/location_share_controller_test.dart
```

기대: 컴파일 실패 — `LocationShareController` 심볼을 찾을 수 없음.

- [ ] **Step 6: `LocationShareController` 구현**

`app/lib/features/group/controllers/location_share_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/location_share_client.dart';

typedef PositionSupplier = Future<({double lat, double lng})> Function();

/// 앱이 포그라운드일 때만, 주입된 tickStream이 방출할 때마다 현재 위치를 서버로 보낸다.
/// 저장은 하지 않는다 — 서버로 보내고 끝이다 (스펙 §6-④).
class LocationShareController {
  LocationShareController({
    required this.client,
    required Stream<void> tickStream,
    required this.currentPosition,
  }) : _tickStream = tickStream;

  final LocationShareClient client;
  final Stream<void> _tickStream;
  final PositionSupplier currentPosition;

  String? _roomId;
  StreamSubscription<void>? _tickSub;
  bool _foreground = true;

  Future<void> start({required String roomId, required String idToken}) async {
    _roomId = roomId;
    await client.connect(idToken);
    _tickSub = _tickStream.listen((_) => _onTick());
  }

  Future<void> stop() async {
    await _tickSub?.cancel();
    _tickSub = null;
    _roomId = null;
    await client.disconnect();
  }

  void onAppLifecycleChanged(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  Future<void> _onTick() async {
    final roomId = _roomId;
    if (roomId == null || !_foreground) return;
    final position = await currentPosition();
    client.sendLocation(roomId: roomId, lat: position.lat, lng: position.lng);
  }
}
```

- [ ] **Step 7: 테스트 통과 확인**

```bash
cd app && flutter test test/group/location_share_controller_test.dart
```

기대: 4개 테스트 모두 PASS.

- [ ] **Step 8: provider 작성**

`app/lib/features/group/providers/location_share_providers.dart`:

```dart
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../controllers/location_share_controller.dart';
import '../data/location_share_client.dart';
import 'group_providers.dart';

/// 위치공유 ON/OFF 토글. 기본값 OFF — 스펙 §6-④.
final locationSharingEnabledProvider = StateProvider<bool>((ref) => false);

final locationShareClientProvider = Provider<LocationShareClient>((ref) {
  final client = StompLocationShareClient(wsUrl: resolveWsUrl(isAndroid: Platform.isAndroid));
  ref.onDispose(() => client.disconnect());
  return client;
});

final locationShareControllerProvider = Provider<LocationShareController>((ref) {
  final client = ref.watch(locationShareClientProvider);
  final controller = LocationShareController(
    client: client,
    tickStream: Stream.periodic(const Duration(seconds: 5)),
    currentPosition: () async {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return (lat: position.latitude, lng: position.longitude);
    },
  );
  ref.onDispose(() => controller.stop());
  return controller;
});

final groupLocationsProvider =
    StreamProvider.family<Map<String, LatLng>, String>((ref, roomId) {
  final client = ref.watch(locationShareClientProvider);
  final myUid = ref.watch(authStateProvider).valueOrNull?.uid;

  final controller = StreamController<Map<String, LatLng>>();
  final positions = <String, LatLng>{};

  final sub = client.subscribeToGroup(roomId).listen((update) {
    if (update.uid == myUid) return; // 내 마커는 기기 자신의 GPS로 따로 그린다
    positions[update.uid] = LatLng(update.lat, update.lng);
    controller.add(Map.of(positions));
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
```

파일 상단에 `import 'dart:async';`를 추가하고, `Geolocator`/`LocationAccuracy` 사용을 위해 `import 'package:geolocator/geolocator.dart';`를 추가한다.

- [ ] **Step 9: `GroupLocationMapPage` 실제 구현**

`app/lib/features/group/screens/group_location_map_page.dart` 전체를 아래로 교체한다. (Plan C의 공용 지도 위젯이 이미 있다면, `GoogleMap(...)` 부분만 그 위젯 호출로 바꾸고 `markers`를 그대로 넘긴다 — 파일 상단 설명 참고.)

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/location_share_providers.dart';

class GroupLocationMapPage extends ConsumerStatefulWidget {
  const GroupLocationMapPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<GroupLocationMapPage> createState() => _GroupLocationMapPageState();
}

class _GroupLocationMapPageState extends ConsumerState<GroupLocationMapPage>
    with WidgetsBindingObserver {
  LatLng? _myPosition;
  StreamSubscription<Position>? _myPositionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(locationShareControllerProvider).onAppLifecycleChanged(state);
  }

  Future<void> _toggleSharing(bool enabled) async {
    ref.read(locationSharingEnabledProvider.notifier).state = enabled;
    final controller = ref.read(locationShareControllerProvider);
    final idToken = await ref.read(authRepositoryProvider).currentIdToken();

    if (enabled && idToken != null) {
      await Geolocator.requestPermission();
      await controller.start(roomId: widget.roomId, idToken: idToken);
      _myPositionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((p) => setState(() => _myPosition = LatLng(p.latitude, p.longitude)));
    } else {
      await controller.stop();
      await _myPositionSub?.cancel();
      _myPositionSub = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _myPositionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(locationSharingEnabledProvider);
    final othersAsync = ref.watch(groupLocationsProvider(widget.roomId));

    final markers = <Marker>{
      if (_myPosition != null)
        Marker(markerId: const MarkerId('me'), position: _myPosition!, infoWindow: const InfoWindow(title: '나')),
      ...othersAsync.valueOrNull?.entries.map(
            (e) => Marker(markerId: MarkerId(e.key), position: e.value, infoWindow: InfoWindow(title: e.key)),
          ) ??
          const <Marker>[],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 위치'),
        actions: [
          Row(
            children: [
              const Text('공유'),
              Switch(value: enabled, onChanged: _toggleSharing),
            ],
          ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _myPosition ?? const LatLng(37.5665, 126.9780), // 기본값: 서울시청
          zoom: 14,
        ),
        markers: markers,
        myLocationEnabled: true,
      ),
    );
  }
}
```

- [ ] **Step 10: Android 위치 권한**

`app/android/app/src/main/AndroidManifest.xml`에 없으면 추가한다.

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Plan C가 이미 발걸음 추적을 위해 같은 권한과 `<meta-data android:name="com.google.android.geo.API_KEY" .../>`(Maps API 키)를 추가했을 수 있다 — 중복 선언은 빌드 오류를 내므로 기존에 있으면 건드리지 않는다.

- [ ] **Step 11: 실기기 2대(또는 에뮬레이터 2개)로 종단 확인**

```bash
cd app && flutter run
```

1. 채팅방 → 위치 아이콘 → 지도 화면 진입
2. 공유 토글 ON → 위치 권한 허용 → 내 마커가 뜬다
3. 다른 기기에서도 같은 방의 지도에서 ON → 서로의 마커가 5초 간격으로 갱신되는지 확인
4. 한쪽에서 앱을 백그라운드로 보내면 그 마커가 더 이상 갱신되지 않는지 확인 (Firestore·PostgreSQL 어디에도 위치가 남지 않는지도 콘솔에서 확인)

- [ ] **Step 12: 전체 검사 실행 및 커밋**

```bash
cd app && flutter analyze && flutter test
git add app/lib/features/group app/test/group app/android/app/src/main/AndroidManifest.xml
git commit -m "feat(app): 실시간 위치공유 — STOMP 클라이언트, 지도 마커, ON/OFF 토글"
```

---

## Self-Review

**1. 스펙 커버리지**
- 6자리 초대 코드 그룹 생성/참여 → Task 1
- 그룹 채팅 → Task 3, DM → Task 4, 사진(Storage) → Task 5, 읽음 표시(`lastReadAt`만 갱신, 메시지 단위 아님) → Task 1(로직) + Task 6(연결)
- FCM 푸시(새 메시지 도착 시) → Task 7
- 실시간 위치공유(포그라운드 5초 STOMP, 미저장, ON/OFF 토글 상시 노출) → Task 8
- Firestore 보안 규칙(그룹 멤버만) → Task 2
- 임의 파일 전송, 낯선 사용자 매칭, 개인 발걸음 기록 → 어느 Task에도 없음 (의도적 제외, Global Constraints에 명시)

**2. 플레이스홀더 스캔**: 전체 Task의 코드 블록에 `TODO`/`구현 예정`/"~와 유사하게" 표현이 없는지 재확인함 — Task 4 Step 7의 `firstOrNull` 대체 코드처럼 팀 의존성에 따라 갈리는 지점은 두 선택지 모두 전체 코드로 제시했다.

**3. 타입/시그니처 일관성 확인**
- `ChatRoom.hasUnreadFor(String uid)` — Task 1에서 정의, Task 1의 `group_page.dart`와 Task 6에서 그대로 사용.
- `GroupRepository.markRead({roomId, uid})` — Task 1에서 정의, Task 6에서 이름 변경 없이 그대로 호출.
- `ChatRepository.sendText`/`sendImage`가 둘 다 `_messages(roomId)`/배치 패턴을 재사용 — Task 3에서 만든 `_messages` getter를 Task 5에서 그대로 재사용.
- `LocationShareClient` 인터페이스가 Task 8 Step 1(정의) → Step 3(Stomp 구현) → Step 6(Controller가 소비) → Step 8(provider가 조립)까지 시그니처 변경 없이 이어짐.
- `AppRoutes.roomDetail`/`roomLocationMap`/`groupCreate`/`groupJoin` — Task 1에서 선언, Task 3·4·8에서 동일한 이름으로 참조.

수정 필요 항목 없음.
