import 'dart:async';
import 'dart:typed_data';

import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/data/chat_room_controller.dart';
import 'package:app/features/group/data/chat_socket.dart';
import 'package:app/features/group/models/chat_message.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_chat_api.dart';
import 'fake_chat_socket.dart';

const _roomId = 1;
const _topic = '/topic/rooms/1/messages';

late FakeChatApi api;
late FakeChatSocket socket;

/// 컨트롤러를 만들고 구독을 유지한 채(화면이 보고 있는 상태) 첫 조회가 끝날 때까지 기다린다.
Future<ProviderContainer> _start() async {
  final container = ProviderContainer(overrides: [
    chatApiProvider.overrideWithValue(api),
    chatSocketProvider.overrideWithValue(socket),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(chatRoomControllerProvider(_roomId), (_, _) {});
  addTearDown(sub.close);
  await _settle();
  return container;
}

/// 마이크로태스크와 가짜 API의 비동기 응답이 끝날 때까지 기다린다.
Future<void> _settle() => Future<void>.delayed(Duration.zero).then((_) => Future<void>.delayed(Duration.zero));

ChatRoomState _state(ProviderContainer c) => c.read(chatRoomControllerProvider(_roomId));
ChatRoomController _controller(ProviderContainer c) => c.read(chatRoomControllerProvider(_roomId).notifier);
List<int> _ids(ProviderContainer c) => [for (final m in _state(c).messages) m.id];

void main() {
  setUp(() {
    api = FakeChatApi();
    socket = FakeChatSocket();
  });
  tearDown(() => socket.dispose());

  group('처음 들어왔을 때', () {
    test('최근 메시지를 최신순으로 불러온다', () async {
      api.storedMessages.addAll([sampleMessage(id: 1), sampleMessage(id: 2), sampleMessage(id: 3)]);

      final c = await _start();

      expect(_state(c).loading, isFalse);
      expect(_ids(c), [3, 2, 1]);
      expect(_state(c).hasMore, isFalse);   // 30개 미만이면 더 없음
    });

    test('그 방의 실시간 토픽을 구독한다', () async {
      await _start();

      expect(socket.activeSubscriptions, {_topic});
    });

    test('멤버가 아닌 방(404)이면 구독하지 않는다 — 공유 연결이 서버에 끊기지 않게', () async {
      api.nextMessagesError = const RoomNotFoundException();

      final c = await _start();

      expect(_state(c).loadError, isA<RoomNotFoundException>());
      expect(socket.activeSubscriptions, isEmpty);
    });

    test('구독은 목록 조회에 성공한 뒤에만 시작하고, 재시도로 성공하면 그때 구독한다', () async {
      api.nextMessagesError = DioException.connectionError(
        requestOptions: RequestOptions(path: '/'), reason: 'offline');
      final c = await _start();
      expect(socket.activeSubscriptions, isEmpty);

      await _controller(c).retry();
      await _settle();

      expect(socket.activeSubscriptions, {_topic});
    });

    test('불러오기에 실패하면 오류 상태가 되고 retry로 다시 시도한다', () async {
      api.storedMessages.add(sampleMessage(id: 1));
      api.nextMessagesError = DioException.connectionError(
        requestOptions: RequestOptions(path: '/'), reason: 'offline');

      final c = await _start();
      expect(_state(c).loadError, isNotNull);

      await _controller(c).retry();

      expect(_state(c).loadError, isNull);
      expect(_ids(c), [1]);
    });
  });

  group('실시간 수신', () {
    test('새 메시지가 오면 맨 앞(최신)에 붙는다', () async {
      api.storedMessages.add(sampleMessage(id: 1));
      final c = await _start();

      socket.emit(_topic, messageJson(sampleMessage(id: 2, text: '공항 도착!')));
      await _settle();

      expect(_ids(c), [2, 1]);
      expect(_state(c).messages.first.text, '공항 도착!');
    });

    test('같은 메시지가 두 번 와도 하나만 남는다', () async {
      final c = await _start();

      socket.emit(_topic, messageJson(sampleMessage(id: 5)));
      socket.emit(_topic, messageJson(sampleMessage(id: 5)));
      await _settle();

      expect(_ids(c), [5]);
    });

    test('순서가 뒤바뀌어 도착해도 id 순으로 정렬된다', () async {
      final c = await _start();

      socket.emit(_topic, messageJson(sampleMessage(id: 7)));
      socket.emit(_topic, messageJson(sampleMessage(id: 6)));
      await _settle();

      expect(_ids(c), [7, 6]);
    });

    test('화면을 떠나면 구독을 해제한다', () async {
      final container = ProviderContainer(overrides: [
        chatApiProvider.overrideWithValue(api),
        chatSocketProvider.overrideWithValue(socket),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(chatRoomControllerProvider(_roomId), (_, _) {});
      await _settle();
      expect(socket.activeSubscriptions, {_topic});

      sub.close();   // 화면이 사라짐 → autoDispose
      await _settle();

      expect(socket.activeSubscriptions, isEmpty);
    });
  });

  group('보내기', () {
    test('보내면 응답 메시지가 바로 목록에 보이고, 같은 메시지가 실시간으로 다시 와도 하나다', () async {
      final c = await _start();

      final ok = await _controller(c).send('  출발합니다  ');
      expect(ok, isTrue);
      expect(api.sentTexts, ['출발합니다']);   // 앞뒤 공백 제거
      final sentId = _ids(c).single;

      // 서버가 같은 메시지를 구독자(나 포함)에게 브로드캐스트
      socket.emit(_topic, messageJson(_state(c).messages.single));
      await _settle();

      expect(_ids(c), [sentId]);
    });

    test('빈 메시지는 보내지 않는다', () async {
      final c = await _start();

      expect(await _controller(c).send('   '), isFalse);
      expect(api.sentTexts, isEmpty);
    });

    test('실패하면 false를 돌려주고 목록은 그대로다', () async {
      api.sendFails = true;
      final c = await _start();

      expect(await _controller(c).send('안녕'), isFalse);
      expect(_state(c).messages, isEmpty);
      expect(_state(c).sending, isFalse);
    });
  });

  group('사진 보내기 (Plan D Task 6)', () {
    final photo = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]);

    test('올리는 동안 자리표시를 두고, 끝나면 사진 메시지로 바꾼다', () async {
      api.holdImage = Completer<void>();
      final c = await _start();

      final sending = _controller(c).sendImage(photo);
      await _settle();
      expect(_state(c).pendingImages.single.bytes, photo);
      expect(_state(c).pendingImages.single.failed, isFalse);
      expect(_state(c).messages, isEmpty);

      api.holdImage!.complete();
      await sending;

      expect(_state(c).pendingImages, isEmpty);
      expect(_state(c).messages.single.type, MessageType.image);
    });

    test('사진마다 다른 업로드 id를 붙인다', () async {
      final c = await _start();

      await _controller(c).sendImage(photo);
      await _controller(c).sendImage(photo);

      expect(api.sentImageClientIds.toSet(), hasLength(2));
    });

    test('브로드캐스트로 같은 사진이 또 와도 하나만 남는다', () async {
      final c = await _start();

      await _controller(c).sendImage(photo);
      socket.emit(_topic, messageJson(_state(c).messages.single));
      await _settle();

      expect(_state(c).messages, hasLength(1));
    });

    test('실패하면 자리표시를 실패로 남기고, 다시 시도하면 같은 사진을 다시 올린다', () async {
      api.nextImageError = DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/rooms/1/images'),
        reason: 'offline',
      );
      final c = await _start();

      await _controller(c).sendImage(photo);
      final pending = _state(c).pendingImages.single;
      expect(pending.failed, isTrue);
      expect(pending.error, isNull, reason: '연결 오류는 다시 시도하면 될 수 있다');

      await _controller(c).retryImage(pending.localId);

      expect(api.sentImages, [photo, photo]);
      expect(api.sentImageClientIds.toSet(), hasLength(1), reason: '다시 시도는 같은 업로드 id로 — 서버가 한 번만 저장한다');
      expect(api.sentImageClientIds.first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(_state(c).pendingImages, isEmpty);
      expect(_state(c).messages.single.type, MessageType.image);
    });

    test('너무 크거나 지원하지 않는 형식이면 이유를 남긴다', () async {
      api.nextImageError = const UnsupportedChatImageException();
      final c = await _start();

      await _controller(c).sendImage(photo);

      expect(_state(c).pendingImages.single.error, contains('형식'));
    });

    test('실패한 자리표시는 지울 수 있다', () async {
      api.nextImageError = const ChatImageTooLargeException();
      final c = await _start();
      await _controller(c).sendImage(photo);

      _controller(c).discardImage(_state(c).pendingImages.single.localId);

      expect(_state(c).pendingImages, isEmpty);
    });
  });

  group('이전 메시지', () {
    test('가장 오래된 id를 before로 넘겨 이어서 가져온다', () async {
      api.storedMessages.addAll([for (var i = 1; i <= 35; i++) sampleMessage(id: i)]);
      final c = await _start();
      expect(_ids(c).length, 30);
      expect(_state(c).hasMore, isTrue);

      await _controller(c).loadOlder();

      expect(api.messageQueries.last.before, 6);   // 첫 페이지의 가장 오래된 id
      expect(_ids(c).length, 35);
      expect(_ids(c).last, 1);
      expect(_state(c).hasMore, isFalse);
    });

    test('더 없으면 다시 부르지 않는다', () async {
      api.storedMessages.add(sampleMessage(id: 1));
      final c = await _start();
      final calls = api.messageQueries.length;

      await _controller(c).loadOlder();

      expect(api.messageQueries.length, calls);
    });
  });

  group('재연결', () {
    test('끊긴 동안 온 메시지를 REST로 받아 채운다', () async {
      api.storedMessages.addAll([sampleMessage(id: 1), sampleMessage(id: 2)]);
      final c = await _start();

      // 끊긴 동안 서버에 쌓인 메시지 (실시간으로는 오지 않았다)
      api.storedMessages.addAll([sampleMessage(id: 3), sampleMessage(id: 4)]);
      socket.emitConnected();
      await _settle();

      expect(_ids(c), [4, 3, 2, 1]);
    });

    test('빈 구간이 한 페이지보다 길면 이미 가진 메시지를 만날 때까지 거슬러 올라간다', () async {
      api.storedMessages.add(sampleMessage(id: 1));
      final c = await _start();

      api.storedMessages.addAll([for (var i = 2; i <= 70; i++) sampleMessage(id: i)]);
      socket.emitConnected();
      for (var i = 0; i < 5; i++) {
        await _settle();
      }

      expect(_ids(c).length, 70);
      expect(_ids(c).first, 70);
      expect(_ids(c).last, 1);
    });
    test('빈 구간이 보충 한도보다 길면, 위로 스크롤할 때 중간을 건너뛰지 않고 이어서 불러온다', () async {
      api.storedMessages.addAll([for (var i = 1; i <= 10; i++) sampleMessage(id: i)]);
      final c = await _start();

      // 끊긴 동안 한도(5페이지 × 30개 = 150개)보다 많이 쌓였다.
      api.storedMessages.addAll([for (var i = 11; i <= 400; i++) sampleMessage(id: i)]);
      socket.emitConnected();
      for (var i = 0; i < 8; i++) {
        await _settle();
      }

      // 가장 최근 150개(400~251)까지만 채웠다. 그 아래는 251과 이어지지 않으므로 목록에 두지 않는다.
      expect(_ids(c).first, 400);
      expect(_ids(c).last, 251);
      expect(_state(c).hasMore, isTrue);

      await _controller(c).loadOlder();

      // 이어서 250부터 불러와야 한다 — 예전 꼬리(1) 아래를 물어 중간(11~250)을 영영 못 보게 되면 안 된다.
      expect(_ids(c).last, 221);
      final ids = _ids(c);
      for (var i = 1; i < ids.length; i++) {
        expect(ids[i - 1] - ids[i], 1, reason: '${ids[i - 1]}와 ${ids[i]} 사이가 비었다');
      }
    });
    test('보충이 목록을 줄인 뒤 늦게 도착한 이전 페이지 응답은 버린다 — 줄여 둔 구멍이 다시 생기지 않게', () async {
      api.storedMessages.addAll([for (var i = 1; i <= 40; i++) sampleMessage(id: i)]);
      final c = await _start();
      expect(_state(c).hasMore, isTrue); // 40..11을 받았다

      // 사용자가 위로 스크롤해 이전 페이지(11 아래)를 요청했는데 응답이 늦다.
      final slowOlder = Completer<void>();
      api.holdBefore[11] = slowOlder;
      final older = _controller(c).loadOlder();
      await _settle();

      // 그 사이 재접속해 한도보다 긴 빈 구간을 채우고 목록을 400~251로 줄였다.
      api.storedMessages.addAll([for (var i = 41; i <= 400; i++) sampleMessage(id: i)]);
      socket.emitConnected();
      for (var i = 0; i < 8; i++) {
        await _settle();
      }
      expect(_ids(c).last, 251);

      slowOlder.complete();
      await older;

      expect(_ids(c).last, 251, reason: '줄이기 전 커서로 받은 오래된 메시지(10~1)가 다시 들어오면 안 된다');
      expect(_state(c).loadingMore, isFalse);

      await _controller(c).loadOlder();
      expect(_ids(c).last, 221);
    });
  });
}
