import 'dart:async';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/data/chat_socket.dart';
import 'package:app/features/group/data/location_share_session.dart';
import 'package:app/features/group/models/room.dart';
import 'package:app/features/nearby/location/location_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'fake_chat_api.dart';
import 'fake_chat_socket.dart';

const _topic = '/topic/group/7/location';

RoomDetail _room() => const RoomDetail(
      id: 7,
      type: RoomType.group,
      name: '도쿄 여행',
      inviteCode: 'ABC234',
      members: [
        RoomMember(uid: 'uid-a', displayName: '성주'),
        RoomMember(uid: 'uid-b', displayName: '민준'),
      ],
    );

/// GPS 대역. 부를 때마다 [next]를 돌려주고, [error]가 있으면 그걸 던진다.
class _FakePosition {
  LatLng next = const LatLng(35.68, 139.76);
  Object? error;
  int calls = 0;

  /// 정해 두면 이 Completer가 끝날 때까지 답하지 않는다 — GPS가 늦게 잡히는 경우.
  Completer<void>? hold;

  Future<LatLng> read() async {
    calls++;
    final h = hold;
    if (h != null) await h.future;
    final e = error;
    if (e != null) throw e;
    return next;
  }
}

class _Harness {
  _Harness() {
    api.detailToReturn = _room();
  }

  final api = FakeChatApi();
  final socket = FakeChatSocket();
  final ticks = StreamController<void>.broadcast();
  final position = _FakePosition();
  DateTime now = DateTime(2026, 10, 18, 12);
  late final ProviderContainer container;
  late final ProviderSubscription<LocationShareState> _screen;

  Future<void> start() async {
    container = ProviderContainer(overrides: [
      chatApiProvider.overrideWithValue(api),
      chatSocketProvider.overrideWithValue(socket),
      currentUidProvider.overrideWithValue('uid-a'),
      locationShareTickerProvider.overrideWithValue(() => ticks.stream),
      locationShareReaderProvider.overrideWithValue(position.read),
      locationShareClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(() {
      container.dispose();
      ticks.close();
      socket.dispose();
    });
    _screen = container.listen(locationShareSessionProvider(7), (_, _) {}); // 화면이 보고 있는 것처럼
    await pumpEventQueue();
  }

  /// 화면을 떠난다 — 보던 쪽이 없어지면 autoDispose로 세션이 정리된다.
  Future<void> leave() async {
    _screen.close();
    await pumpEventQueue();
  }

  LocationShareState get state => container.read(locationShareSessionProvider(7));
  LocationShareSession get session => container.read(locationShareSessionProvider(7).notifier);

  Future<void> tick() async {
    ticks.add(null);
    await pumpEventQueue();
  }

  List<Map<String, dynamic>> get sentLocations =>
      [for (final s in socket.sent) if (s.destination == '/app/location') s.body];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('방 정보를 받은 뒤에(멤버임이 확인된 뒤에) 위치를 구독한다', () async {
    final h = _Harness();
    await h.start();

    expect(h.state.room?.name, '도쿄 여행');
    expect(h.socket.activeSubscriptions, {_topic});
  });

  test('멤버가 아니면(404) 구독하지 않는다 — 공유 연결이 서버에 끊기지 않게', () async {
    final h = _Harness();
    h.api.roomDetailNotFound = true;
    await h.start();

    expect(h.state.loadError, isA<RoomNotFoundException>());
    expect(h.socket.activeSubscriptions, isEmpty);
  });

  test('DM 방이면 위치공유를 열지 않고 구독하지 않는다 (그룹 방 기능)', () async {
    final h = _Harness();
    h.api.detailToReturn = const RoomDetail(
      id: 7,
      type: RoomType.dm,
      members: [RoomMember(uid: 'uid-a'), RoomMember(uid: 'uid-b')],
    );
    await h.start();

    expect(h.state.loadError, isA<LocationShareGroupOnly>());
    expect(h.socket.activeSubscriptions, isEmpty);
  });

  test('GPS를 읽는 중에 껐다 다시 켜도 켜진 상태가 유지된다', () async {
    final h = _Harness();
    await h.start();
    await h.session.setSharing(true);
    h.position.hold = Completer<void>();
    await h.tick(); // 틱의 읽기가 멈춰 있다

    await h.session.setSharing(false);
    final turningOn = h.session.setSharing(true); // 앞선 읽기가 끝나길 기다린다
    h.position.hold!.complete();
    await turningOn;

    expect(h.state.sharing, isTrue);
    expect(h.sentLocations, hasLength(2), reason: '처음 켤 때 + 다시 켤 때(끈 사이 끝난 틱 읽기는 버린다)');

    h.position.hold = null;
    await h.tick();
    expect(h.sentLocations, hasLength(3), reason: '다시 켠 뒤로 틱마다 보낸다');
  });

  test('공유는 꺼진 채로 시작하고, 꺼져 있으면 틱이 와도 보내지 않는다', () async {
    final h = _Harness();
    await h.start();

    await h.tick();

    expect(h.state.sharing, isFalse);
    expect(h.sentLocations, isEmpty);
    expect(h.position.calls, 0, reason: '꺼져 있으면 GPS도 켜지 않는다');
  });

  test('켜면 바로 한 번 보내고, 그 뒤로 틱마다 보낸다', () async {
    final h = _Harness();
    await h.start();

    await h.session.setSharing(true);
    expect(h.sentLocations, [
      {'roomId': '7', 'lat': 35.68, 'lng': 139.76, 'ts': h.now.millisecondsSinceEpoch},
    ]);
    expect(h.state.sharing, isTrue);
    expect(h.state.me, const LatLng(35.68, 139.76));

    h.position.next = const LatLng(35.69, 139.70);
    await h.tick();

    expect(h.sentLocations, hasLength(2));
    expect(h.sentLocations.last['lat'], 35.69);
    expect(h.state.me, const LatLng(35.69, 139.70));
  });

  test('끄면 틱이 와도 더는 보내지 않는다', () async {
    final h = _Harness();
    await h.start();
    await h.session.setSharing(true);

    await h.session.setSharing(false);
    await h.tick();

    expect(h.sentLocations, hasLength(1));
    expect(h.state.sharing, isFalse);
  });

  test('위치 권한이 없으면 켜지지 않고 안내한다', () async {
    final h = _Harness();
    await h.start();
    h.position.error = const LocationPermissionDeniedException();

    await h.session.setSharing(true);

    expect(h.state.sharing, isFalse);
    expect(h.state.notice, contains('권한'));
    expect(h.sentLocations, isEmpty);
  });

  test('위치 서비스가 꺼져 있으면 켜지지 않고 안내한다', () async {
    final h = _Harness();
    await h.start();
    h.position.error = const LocationServiceDisabledException();

    await h.session.setSharing(true);

    expect(h.state.sharing, isFalse);
    expect(h.state.notice, contains('위치 서비스'));
  });

  test('앱이 백그라운드에 있는 동안은 보내지 않고, 돌아오면 다시 보낸다', () async {
    final h = _Harness();
    await h.start();
    await h.session.setSharing(true);
    final binding = TestWidgetsFlutterBinding.instance;
    addTearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await h.tick();
    expect(h.sentLocations, hasLength(1), reason: '백그라운드에서는 GPS도 읽지 않는다');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.tick();
    expect(h.sentLocations, hasLength(2));
  });

  test('GPS를 읽는 사이 앱이 뒤로 가면 읽은 위치를 보내지 않는다', () async {
    final h = _Harness();
    await h.start();
    await h.session.setSharing(true);
    final binding = TestWidgetsFlutterBinding.instance;
    addTearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    h.position.hold = Completer<void>();

    await h.tick(); // 읽기 시작(아직 안 끝남)
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    h.position.hold!.complete();
    await pumpEventQueue();

    expect(h.sentLocations, hasLength(1), reason: '켤 때 보낸 것뿐');
  });

  test('GPS가 늦어도 앞선 읽기가 끝나기 전에는 겹쳐 읽지 않는다', () async {
    final h = _Harness();
    await h.start();
    await h.session.setSharing(true);
    h.position.hold = Completer<void>();

    await h.tick();
    await h.tick();
    h.position.hold!.complete();
    await pumpEventQueue();

    expect(h.position.calls, 2, reason: '켤 때 1번 + 늦은 읽기 1번');
    expect(h.sentLocations, hasLength(2));
  });

  test('그룹원의 위치를 받아 이름과 함께 들고 있고, 내 위치 방송은 무시한다', () async {
    final h = _Harness();
    await h.start();

    h.socket.emit(_topic, {'uid': 'uid-b', 'lat': 35.7, 'lng': 139.8, 'ts': 1});
    h.socket.emit(_topic, {'uid': 'uid-a', 'lat': 0.0, 'lng': 0.0, 'ts': 1});
    await pumpEventQueue();

    expect(h.state.others.keys, ['uid-b']);
    expect(h.state.others['uid-b']!.position, const LatLng(35.7, 139.8));
    expect(h.state.me, isNull, reason: '내 마커는 이 기기의 GPS로만 그린다');
  });

  test('형식이 맞지 않는 방송은 버린다', () async {
    final h = _Harness();
    await h.start();

    h.socket.emit(_topic, {'uid': 'uid-b', 'lat': 'north'});
    h.socket.emit(_topic, {'lat': 1.0, 'lng': 2.0});
    await pumpEventQueue();

    expect(h.state.others, isEmpty);
  });

  test('20초 넘게 소식이 없는 그룹원은 꺼진 것으로 본다', () async {
    final h = _Harness();
    await h.start();
    h.socket.emit(_topic, {'uid': 'uid-b', 'lat': 35.7, 'lng': 139.8, 'ts': 1});
    await pumpEventQueue();
    expect(h.state.isStale('uid-b'), isFalse);

    h.now = h.now.add(const Duration(seconds: 21));
    await h.tick(); // 틱마다 시계를 다시 읽어 화면을 갱신한다

    expect(h.state.isStale('uid-b'), isTrue);
  });

  test('화면을 떠나면 구독과 틱을 멈춘다', () async {
    final h = _Harness();
    await h.start();
    await h.session.setSharing(true);

    await h.leave();
    h.ticks.add(null);
    await pumpEventQueue();

    expect(h.socket.activeSubscriptions, isEmpty);
    expect(h.sentLocations, hasLength(1));
  });
}
