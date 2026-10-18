import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/group/chat_room_page.dart';
import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/data/chat_socket.dart';
import 'package:app/features/group/models/room.dart';
import 'package:app/router.dart';
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

Future<(FakeChatApi, FakeChatSocket)> _pump(WidgetTester tester, {FakeChatApi? api}) async {
  final chatApi = api ?? (FakeChatApi()..detailToReturn = _room());
  final socket = FakeChatSocket();
  addTearDown(socket.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      chatApiProvider.overrideWithValue(chatApi),
      chatSocketProvider.overrideWithValue(socket),
      currentUidProvider.overrideWithValue('uid-a'),
    ],
    child: const MaterialApp(home: Scaffold(body: ChatRoomPage(roomId: 1))),
  ));
  await tester.pumpAndSettle();
  return (chatApi, socket);
}

void main() {
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
