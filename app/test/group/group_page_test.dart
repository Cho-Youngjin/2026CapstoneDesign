import 'package:app/core/auth/app_user.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/group_page.dart';
import 'package:app/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_chat_api.dart';

/// 그룹 탭 + 채팅방 자리만 있는 최소 라우터로 GroupPage를 띄운다.
/// 채팅방 화면은 Plan D Task 4에서 만들므로 여기서는 "어느 방으로 이동했는지"만 본다.
Future<void> _pump(WidgetTester tester, FakeChatApi api, {FakeAuthRepository? auth}) async {
  final authRepo = auth ?? (FakeAuthRepository()..signIn(const AppUser(uid: 'uid-a', displayName: '성주')));
  addTearDown(authRepo.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.group,
    routes: [
      GoRoute(path: AppRoutes.group, builder: (_, _) => const Scaffold(body: GroupPage())),
      GoRoute(
        path: AppRoutes.groupChat,
        builder: (context, state) => Scaffold(
          body: Column(children: [
            Text('채팅방 ${state.pathParameters['roomId']}'),
            TextButton(onPressed: () => context.pop(), child: const Text('뒤로')),
          ]),
        ),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      authRepositoryProvider.overrideWithValue(authRepo),
      // 실제 앱에서 그룹 탭은 로그인이 확정된 뒤에만 보인다. 테스트에서도 uid를 처음부터 고정해,
      // 로그인 상태가 한 프레임 늦게 확정되면서 목록을 두 번 불러오는 일이 없게 한다.
      currentUidProvider.overrideWithValue(authRepo.currentUser?.uid),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('방 목록', () {
    testWidgets('내 방들을 이름·인원·미리보기·안 읽은 수와 함께 보여준다', (tester) async {
      final api = FakeChatApi(rooms: [
        sampleRoom(id: 2, name: '다낭 4인방', memberCount: 4, preview: '공항 도착!',
            lastMessageAt: DateTime(2026, 10, 16, 14, 14), unreadCount: 12),
        sampleRoom(id: 1, name: '도쿄 여행', memberCount: 1),
      ]);

      await _pump(tester, api);

      expect(find.text('다낭 4인방'), findsOneWidget);
      expect(find.text('그룹 4'), findsOneWidget);
      expect(find.text('공항 도착!'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('도쿄 여행'), findsOneWidget);
      expect(find.text('아직 메시지가 없어요'), findsOneWidget);   // 메시지 없는 방
    });

    testWidgets('목록을 불러오기 전에 내 프로필을 서버에 올린다', (tester) async {
      final api = FakeChatApi();

      await _pump(tester, api);

      expect(api.profileUploads, [(displayName: '성주', photoUrl: null)]);
    });

    testWidgets('방이 없으면 만들기·참여를 안내한다', (tester) async {
      await _pump(tester, FakeChatApi());

      expect(find.byKey(const Key('emptyRooms')), findsOneWidget);
    });

    testWidgets('불러오기에 실패하면 오류를 보여주고 다시 시도할 수 있다', (tester) async {
      final api = FakeChatApi(rooms: [sampleRoom(name: '복구된 방')])
        ..nextMyRoomsError = DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/rooms'),
          reason: 'offline',
        );

      await _pump(tester, api);
      expect(find.byKey(const Key('roomsError')), findsOneWidget);

      await tester.tap(find.byKey(const Key('roomsRetry')));
      await tester.pumpAndSettle();

      expect(find.text('복구된 방'), findsOneWidget);
    });

    testWidgets('방을 누르면 그 방의 채팅방으로 이동한다', (tester) async {
      await _pump(tester, FakeChatApi(rooms: [sampleRoom(id: 7, name: '오사카')]));

      await tester.tap(find.text('오사카'));
      await tester.pumpAndSettle();

      expect(find.text('채팅방 7'), findsOneWidget);
    });

    testWidgets('채팅방에서 돌아오면 목록을 다시 불러와 최근 메시지를 갱신한다', (tester) async {
      final api = FakeChatApi(rooms: [sampleRoom(id: 7, name: '오사카', preview: '예전 메시지')]);
      await _pump(tester, api);
      await tester.tap(find.text('오사카'));
      await tester.pumpAndSettle();

      // 채팅방에서 메시지를 주고받았다
      api.rooms = [sampleRoom(id: 7, name: '오사카', preview: '방금 보낸 메시지')];
      await tester.tap(find.text('뒤로'));
      await tester.pumpAndSettle();

      expect(find.text('방금 보낸 메시지'), findsOneWidget);
      expect(find.text('예전 메시지'), findsNothing);
    });
  });

  group('그룹 만들기', () {
    testWidgets('이름을 넣고 만들면 초대 코드를 보여주고 목록이 갱신된다', (tester) async {
      final api = FakeChatApi()..detailToReturn = sampleDetail(id: 9, name: '삿포로', inviteCode: 'QWE234');
      await _pump(tester, api);

      await tester.tap(find.byKey(const Key('createGroupButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createGroupName')), '  삿포로  ');
      await tester.pump(); // 입력이 반영돼 버튼이 켜진 화면을 그린 뒤에 누른다
      api.rooms = [sampleRoom(id: 9, name: '삿포로')];   // 만든 뒤 서버 목록
      await tester.tap(find.byKey(const Key('createGroupSubmit')));
      await tester.pumpAndSettle();

      expect(api.createdNames, ['삿포로']);   // 앞뒤 공백 제거
      expect(find.byKey(const Key('inviteCodeDialog')), findsOneWidget);
      expect(find.text('QWE234'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inviteCodeClose')));
      await tester.pumpAndSettle();
      expect(find.text('삿포로'), findsOneWidget);   // 새로 고친 목록에 보인다
    });

    testWidgets('초대 코드를 복사할 수 있다', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final api = FakeChatApi()..detailToReturn = sampleDetail(inviteCode: 'QWE234');
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('createGroupButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createGroupName')), '삿포로');
      await tester.pump();
      await tester.tap(find.byKey(const Key('createGroupSubmit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inviteCodeCopy')));
      await tester.pump();

      expect(copied, ['QWE234']);
    });

    testWidgets('이름이 비어 있으면 만들 수 없다', (tester) async {
      final api = FakeChatApi();
      await _pump(tester, api);

      await tester.tap(find.byKey(const Key('createGroupButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('createGroupName')), '   ');
      await tester.pump();

      final submit = tester.widget<FilledButton>(find.byKey(const Key('createGroupSubmit')));
      expect(submit.onPressed, isNull);
    });
  });

  group('코드로 참여', () {
    testWidgets('소문자로 입력해도 대문자로 보내고, 참여한 방으로 이동한다', (tester) async {
      final api = FakeChatApi()..detailToReturn = sampleDetail(id: 4);
      await _pump(tester, api);

      await tester.tap(find.byKey(const Key('joinGroupButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('joinCodeField')), 'abc234');
      await tester.pump();
      await tester.tap(find.byKey(const Key('joinSubmit')));
      await tester.pumpAndSettle();

      expect(api.joinedCodes, ['ABC234']);
      expect(find.text('채팅방 4'), findsOneWidget);
    });

    testWidgets('6자리가 아니면 참여할 수 없다', (tester) async {
      await _pump(tester, FakeChatApi());

      await tester.tap(find.byKey(const Key('joinGroupButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('joinCodeField')), 'ABC23');
      await tester.pump();

      final submit = tester.widget<FilledButton>(find.byKey(const Key('joinSubmit')));
      expect(submit.onPressed, isNull);
    });

    testWidgets('없는 코드면 안내를 보여주고 시트에 남는다', (tester) async {
      final api = FakeChatApi()..joinNotFound = true;
      await _pump(tester, api);

      await tester.tap(find.byKey(const Key('joinGroupButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('joinCodeField')), 'ZZZZZZ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('joinSubmit')));
      await tester.pumpAndSettle();

      expect(find.text('코드를 찾을 수 없어요. 다시 확인해 주세요.'), findsOneWidget);
      expect(find.byKey(const Key('joinCodeField')), findsOneWidget);   // 다시 입력할 수 있다
    });

    testWidgets('목록 아래 초대 코드 카드로도 참여 시트를 연다', (tester) async {
      await _pump(tester, FakeChatApi(rooms: [sampleRoom()]));

      await tester.tap(find.byKey(const Key('inviteCodeCard')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('joinCodeField')), findsOneWidget);
    });
  });

  group('formatRoomTime', () {
    final now = DateTime(2026, 10, 16, 18, 0);

    test('오늘은 오전/오후 시각', () {
      expect(formatRoomTime(DateTime(2026, 10, 16, 14, 14), now), '오후 2:14');
      expect(formatRoomTime(DateTime(2026, 10, 16, 9, 5), now), '오전 9:05');
      expect(formatRoomTime(DateTime(2026, 10, 16, 0, 30), now), '오전 12:30');
      expect(formatRoomTime(DateTime(2026, 10, 16, 12, 0), now), '오후 12:00');
    });

    test('어제는 "어제"', () {
      expect(formatRoomTime(DateTime(2026, 10, 15, 23, 59), now), '어제');
    });

    test('올해 그 전은 월/일, 작년 이전은 연/월/일', () {
      expect(formatRoomTime(DateTime(2026, 4, 9, 10, 0), now), '04/09');
      expect(formatRoomTime(DateTime(2025, 12, 31, 10, 0), now), '2025/12/31');
    });
  });

  test('RoomNotFoundException은 예외다', () {
    expect(const RoomNotFoundException(), isA<Exception>());
  });
}
