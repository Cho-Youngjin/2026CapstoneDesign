import 'dart:typed_data';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/group/chat_room_page.dart';
import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/data/chat_images.dart';
import 'package:app/features/group/data/chat_socket.dart';
import 'package:app/features/group/models/room.dart';
import 'package:app/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_chat_api.dart';
import 'fake_chat_socket.dart';

const _topic = '/topic/rooms/1/messages';

/// 방 1: 성주(나, uid-a)와 영진(uid-b) 두 명.
RoomDetail _room({List<RoomMember>? members}) => RoomDetail(
      id: 1,
      type: RoomType.group,
      name: '다낭 4인방',
      inviteCode: 'ABC234',
      members: members ??
          const [
            RoomMember(uid: 'uid-a', displayName: '성주'),
            RoomMember(uid: 'uid-b', displayName: '영진'),
          ],
    );

Future<(FakeChatApi, FakeChatSocket)> _pump(
  WidgetTester tester, {
  FakeChatApi? api,
  Future<Uint8List?> Function()? picker,
}) async {
  final chatApi = api ?? (FakeChatApi()..detailToReturn = _room());
  final socket = FakeChatSocket();
  addTearDown(socket.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      chatApiProvider.overrideWithValue(chatApi),
      chatSocketProvider.overrideWithValue(socket),
      currentUidProvider.overrideWithValue('uid-a'),
      chatImagePickerProvider.overrideWithValue(picker ?? () async => null),
    ],
    child: const MaterialApp(home: Scaffold(body: ChatRoomPage(roomId: 1))),
  ));
  await tester.pumpAndSettle();
  return (chatApi, socket);
}

/// 채팅방 1을 라우터로 띄운다. 다른 방(DM 등)으로 이동하면 그 자리에는 "채팅 {id}" 글자만 그린다.
Future<FakeChatApi> _pumpRouted(WidgetTester tester, FakeChatApi api) async {
  final socket = FakeChatSocket();
  addTearDown(socket.dispose);
  final router = GoRouter(
    initialLocation: '/group/chat/1',
    routes: [
      GoRoute(
        path: '/group/chat/:roomId',
        builder: (_, state) => state.pathParameters['roomId'] == '1'
            ? const Scaffold(body: ChatRoomPage(roomId: 1))
            : Scaffold(body: Text('채팅 ${state.pathParameters['roomId']}')),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatSocketProvider.overrideWithValue(socket),
      currentUidProvider.overrideWithValue('uid-a'),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return api;
}

const _dm = RoomDetail(
  id: 30,
  type: RoomType.dm,
  members: [RoomMember(uid: 'uid-a', displayName: '성주'), RoomMember(uid: 'uid-b', displayName: '영진')],
);

void main() {
  group('읽음 표시 (Plan D Task 7)', () {
    // 성주(나)가 보낸 5번 메시지. 영진은 아직 안 읽었고(위치 없음), 민준은 10번까지 읽었다.
    RoomDetail threeMembers() => _room(members: const [
          RoomMember(uid: 'uid-a', displayName: '성주'),
          RoomMember(uid: 'uid-b', displayName: '영진'),
          RoomMember(uid: 'uid-c', displayName: '민준', lastReadMessageId: 10),
        ]);

    testWidgets('메시지 옆에 아직 안 읽은 멤버 수를 보여준다(보낸 사람 제외)', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = threeMembers()
        ..storedMessages.add(sampleMessage(id: 5, senderUid: 'uid-a'));

      await _pump(tester, api: api);

      expect(find.byKey(const Key('unread-5')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('unread-5'))).data, '1');
    });

    testWidgets('읽었다는 소식이 오면 그 수가 줄고, 모두 읽으면 표시가 사라진다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = threeMembers()
        ..storedMessages.add(sampleMessage(id: 5, senderUid: 'uid-a'));
      final (_, socket) = await _pump(tester, api: api);

      socket.emit('/topic/rooms/1/read', {'roomId': 1, 'uid': 'uid-b', 'lastReadMessageId': 5});
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unread-5')), findsNothing);
    });

    testWidgets('화면을 연 뒤 들어온 멤버도 읽음 소식으로 알게 되면 안 읽은 수에 센다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = threeMembers()
        ..storedMessages.addAll([sampleMessage(id: 5, senderUid: 'uid-a'), sampleMessage(id: 20, senderUid: 'uid-a')]);
      final (_, socket) = await _pump(tester, api: api);
      expect(tester.widget<Text>(find.byKey(const Key('unread-20'))).data, '2', reason: '영진·민준');

      // 방 정보에 없던 지훈이 들어와 5번까지 읽었다 — 20번은 아직 안 읽었다.
      socket.emit('/topic/rooms/1/read', {'roomId': 1, 'uid': 'uid-new', 'lastReadMessageId': 5});
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('unread-20'))).data, '3');
    });

    testWidgets('채팅방을 열면 잠시 뒤 가장 최근 메시지까지 읽었다고 알린다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = threeMembers()
        ..storedMessages.addAll([sampleMessage(id: 4), sampleMessage(id: 9)]);

      await _pump(tester, api: api);
      expect(api.readMarks, isEmpty, reason: '1초 디바운스 전');
      await tester.pump(const Duration(seconds: 1));

      expect(api.readMarks, [9]);
    });
  });

  group('사진 (Plan D Task 6)', () {
    testWidgets('사진 메시지는 그 주소로 받은 그림으로 보여준다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = _room()
        ..storedMessages.addAll([sampleImageMessage(id: 5, senderUid: 'uid-b')]);

      await _pump(tester, api: api);

      expect(api.imageDownloads, ['/api/rooms/1/images/5']);
      expect(find.descendant(of: find.byKey(const Key('image-5')), matching: find.byType(Image)), findsOneWidget);
    });

    testWidgets('받은 바이트가 깨진 그림이면 깨진 그림 표시로 대신한다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = _room()
        ..storedMessages.addAll([sampleImageMessage(id: 5, senderUid: 'uid-b')])
        // 앞부분은 JPEG처럼 보이지만 뒤가 잘린 바이트 — 서버의 형식 판정은 통과한다.
        ..imagesByUrl['/api/rooms/1/images/5'] = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

      await _pump(tester, api: api);
      // 그림 해독은 엔진에서 따로 돌므로 실제 시간을 조금 흘려 결과가 돌아오게 한다.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('brokenImage')), findsOneWidget);
    });

    testWidgets('사진을 고르면 올리고, 끝나면 내 사진 말풍선으로 보인다', (tester) async {
      final (api, _) = await _pump(tester, picker: () async => onePixelPng);

      await tester.tap(find.byKey(const Key('attachImage')));
      await tester.pumpAndSettle();

      expect(api.sentImages, [onePixelPng]);
      final sentId = api.storedMessages.single.id;
      expect(find.byKey(Key('image-$sentId')), findsOneWidget);
      expect(find.byKey(const Key('pending-0')), findsNothing);
    });

    testWidgets('고르기를 취소하면 아무것도 보내지 않는다', (tester) async {
      final (api, _) = await _pump(tester, picker: () async => null);

      await tester.tap(find.byKey(const Key('attachImage')));
      await tester.pumpAndSettle();

      expect(api.sentImages, isEmpty);
    });

    testWidgets('올리지 못하면 다시 시도할 수 있다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = _room()
        ..nextImageError = DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/rooms/1/images'),
          reason: 'offline',
        );
      await _pump(tester, api: api, picker: () async => onePixelPng);

      await tester.tap(find.byKey(const Key('attachImage')));
      await tester.pumpAndSettle();
      expect(find.text('사진을 보내지 못했어요.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryImage-0')));
      await tester.pumpAndSettle();

      expect(api.sentImages, hasLength(2));
      expect(find.byKey(const Key('pending-0')), findsNothing);
      expect(find.byKey(Key('image-${api.storedMessages.single.id}')), findsOneWidget);
    });

    testWidgets('형식 때문에 거절되면 다시 시도 대신 지우기만 둔다', (tester) async {
      final api = FakeChatApi()
        ..detailToReturn = _room()
        ..nextImageError = const UnsupportedChatImageException();
      await _pump(tester, api: api, picker: () async => onePixelPng);

      await tester.tap(find.byKey(const Key('attachImage')));
      await tester.pumpAndSettle();

      expect(find.textContaining('형식'), findsOneWidget);
      expect(find.byKey(const Key('retryImage-0')), findsNothing);
      await tester.tap(find.byKey(const Key('discardImage-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending-0')), findsNothing);
    });
  });

  group('멤버 목록과 1:1 DM', () {
    testWidgets('멤버 목록에서 [메시지]를 누르면 그 사람과의 DM 방으로 간다', (tester) async {
      final api = await _pumpRouted(tester, FakeChatApi()
        ..detailToReturn = _room()
        ..dmToReturn = _dm);

      await tester.tap(find.byKey(const Key('openMembers')));
      await tester.pumpAndSettle();
      expect(find.text('성주 (나)'), findsOneWidget);
      expect(find.byKey(const Key('dm-uid-a')), findsNothing, reason: '나에게는 메시지 버튼이 없다');

      await tester.tap(find.byKey(const Key('dm-uid-b')));
      await tester.pumpAndSettle();

      expect(api.openedDmPeers, ['uid-b']);
      expect(find.text('채팅 30'), findsOneWidget);
    });

    testWidgets('같은 그룹이 아니라며 거절되면 시트에 이유를 보여주고 남는다', (tester) async {
      await _pumpRouted(tester, FakeChatApi()..detailToReturn = _room()); // dmToReturn 없음 → 404

      await tester.tap(find.byKey(const Key('openMembers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dm-uid-b')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('membersSheetError')), findsOneWidget);
      expect(find.textContaining('같은 그룹 멤버에게만'), findsOneWidget);
      expect(find.text('채팅 30'), findsNothing);
    });

    testWidgets('DM 방에는 멤버 목록 버튼이 없고 제목은 상대 이름이다', (tester) async {
      await _pump(tester, api: FakeChatApi()..detailToReturn = _dm);

      expect(find.byKey(const Key('openMembers')), findsNothing);
      expect(find.text('영진'), findsOneWidget);
    });
  });

  testWidgets('위치 아이콘은 이 방의 위치공유 화면으로 간다', (tester) async {
    final socket = FakeChatSocket();
    addTearDown(socket.dispose);
    final router = GoRouter(
      initialLocation: '/group/chat/1',
      routes: [
        GoRoute(path: '/group/chat/:roomId', builder: (_, _) => const Scaffold(body: ChatRoomPage(roomId: 1))),
        GoRoute(
          path: AppRoutes.groupLocation,
          builder: (_, state) => Scaffold(body: Text('위치 ${state.pathParameters['roomId']}')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(FakeChatApi()..detailToReturn = _room()),
        chatSocketProvider.overrideWithValue(socket),
        currentUidProvider.overrideWithValue('uid-a'),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openLocationShare')));
    await tester.pumpAndSettle();

    expect(find.text('위치 1'), findsOneWidget);
  });

  testWidgets('DM 방에서는 위치 아이콘을 보여주지 않는다 (위치공유는 그룹 방 기능)', (tester) async {
    await _pump(tester,
        api: FakeChatApi()
          ..detailToReturn = const RoomDetail(
            id: 1,
            type: RoomType.dm,
            members: [RoomMember(uid: 'uid-a', displayName: '성주'), RoomMember(uid: 'uid-b', displayName: '영진')],
          ));

    expect(find.byKey(const Key('openLocationShare')), findsNothing);
  });

  testWidgets('멤버가 아닌 방에서는 위치 아이콘을 보여주지 않는다', (tester) async {
    await _pump(tester, api: FakeChatApi()..roomDetailNotFound = true);

    expect(find.byKey(const Key('roomNotFound')), findsOneWidget);
    expect(find.byKey(const Key('openLocationShare')), findsNothing);
  });

  testWidgets('상단에 방 이름과 인원을 보여준다', (tester) async {
    await _pump(tester);

    expect(find.text('다낭 4인방'), findsOneWidget);
    expect(find.text('2명'), findsOneWidget);
  });

  testWidgets('내 메시지와 상대 메시지를 구분하고, 상대 메시지에는 이름을 붙인다', (tester) async {
    final api = FakeChatApi()
      ..detailToReturn = _room()
      ..storedMessages.addAll([
        sampleMessage(id: 1, senderUid: 'uid-b', text: '다들 공항 왔어?'),
        sampleMessage(id: 2, senderUid: 'uid-a', text: '나 도착!'),
      ]);

    await _pump(tester, api: api);

    expect(find.byKey(const Key('incoming-1')), findsOneWidget);
    expect(find.byKey(const Key('outgoing-2')), findsOneWidget);
    expect(find.text('다들 공항 왔어?'), findsOneWidget);
    expect(find.text('나 도착!'), findsOneWidget);
    expect(find.text('영진'), findsOneWidget);   // 상대 이름
    expect(find.text('성주'), findsNothing);     // 내 이름은 표시하지 않는다
  });

  testWidgets('메시지가 없으면 첫 메시지를 안내한다', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('emptyChat')), findsOneWidget);
  });

  testWidgets('날짜가 바뀌는 곳에 날짜 구분선을 넣는다', (tester) async {
    final api = FakeChatApi()
      ..detailToReturn = _room()
      ..storedMessages.addAll([
        sampleMessage(id: 1, createdAt: DateTime(2026, 10, 16, 23, 50)),
        sampleMessage(id: 2, createdAt: DateTime(2026, 10, 17, 0, 10)),
      ]);

    await _pump(tester, api: api);

    expect(find.text('2026년 10월 16일'), findsOneWidget);
    expect(find.text('2026년 10월 17일'), findsOneWidget);
  });

  testWidgets('실시간으로 온 메시지가 바로 보인다', (tester) async {
    final (_, socket) = await _pump(tester);

    socket.emit(_topic, messageJson(sampleMessage(id: 9, senderUid: 'uid-b', text: '숙소 체크인 완료')));
    await tester.pumpAndSettle();

    expect(find.text('숙소 체크인 완료'), findsOneWidget);
  });

  testWidgets('입력하고 보내면 내 메시지로 보이고 입력창이 비워진다', (tester) async {
    final (api, _) = await _pump(tester);

    await tester.enterText(find.byKey(const Key('chatInput')), '출발합니다');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatSend')));
    await tester.pumpAndSettle();

    expect(api.sentTexts, ['출발합니다']);
    expect(find.text('출발합니다'), findsOneWidget);   // 말풍선 (입력창은 비었으므로 하나)
    final input = tester.widget<TextField>(find.byKey(const Key('chatInput')));
    expect(input.controller!.text, isEmpty);
  });

  testWidgets('입력이 비어 있으면 보내기 버튼이 꺼져 있다', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('chatInput')), '   ');
    await tester.pump();

    final send = tester.widget<IconButton>(find.byKey(const Key('chatSend')));
    expect(send.onPressed, isNull);
  });

  testWidgets('보내기에 실패하면 안내하고 입력한 글은 남겨 둔다', (tester) async {
    final api = FakeChatApi()
      ..detailToReturn = _room()
      ..sendFails = true;
    await _pump(tester, api: api);

    await tester.enterText(find.byKey(const Key('chatInput')), '다시 보낼 글');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatSend')));
    await tester.pumpAndSettle();

    expect(find.text('전송하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    final input = tester.widget<TextField>(find.byKey(const Key('chatInput')));
    expect(input.controller!.text, '다시 보낼 글');
  });

  testWidgets('목록에 없는 사람이 보낸 메시지가 오면 멤버 정보를 다시 불러온다', (tester) async {
    final (api, socket) = await _pump(tester);
    // 그사이 새 멤버가 참여했다
    api.detailToReturn = _room(members: const [
      RoomMember(uid: 'uid-a', displayName: '성주'),
      RoomMember(uid: 'uid-b', displayName: '영진'),
      RoomMember(uid: 'uid-c', displayName: '새친구'),
    ]);

    socket.emit(_topic, messageJson(sampleMessage(id: 3, senderUid: 'uid-c', text: '저도 왔어요')));
    await tester.pumpAndSettle();

    expect(find.text('새친구'), findsOneWidget);
    expect(find.text('3명'), findsOneWidget);
  });

  testWidgets('멤버가 아닌 방이면 안내만 보여준다', (tester) async {
    final api = _NotFoundChatApi();

    await _pump(tester, api: api);

    expect(find.byKey(const Key('roomNotFound')), findsOneWidget);
    expect(find.byKey(const Key('chatInput')), findsNothing);
  });

  group('formatClock', () {
    test('오전/오후 시각', () {
      expect(formatClock(DateTime(2026, 10, 17, 14, 5)), '오후 2:05');
      expect(formatClock(DateTime(2026, 10, 17, 0, 0)), '오전 12:00');
    });
  });
}

class _NotFoundChatApi extends FakeChatApi {
  @override
  Future<RoomDetail> roomDetail(int roomId) async => throw const RoomNotFoundException();
}
