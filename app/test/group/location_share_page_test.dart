import 'dart:async';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/footsteps/map/base_google_map.dart';
import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/data/chat_socket.dart';
import 'package:app/features/group/data/location_share_session.dart';
import 'package:app/features/group/location_share_page.dart';
import 'package:app/features/group/models/room.dart';
import 'package:app/features/nearby/location/location_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'fake_chat_api.dart';
import 'fake_chat_socket.dart';

/// GoogleMap이 실제 플랫폼 뷰를 요구해 위젯 테스트가 멈추므로 빈 위젯을 그리는 가짜로 바꾼다
/// (country_detail_map_page_test.dart와 같은 이유).
class _FakeGoogleMapsFlutterPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> init(int mapId) async {}
}

const _topic = '/topic/group/7/location';

RoomDetail _room() => const RoomDetail(
      id: 7,
      type: RoomType.group,
      name: '도쿄 여행',
      inviteCode: 'ABC234',
      members: [
        RoomMember(uid: 'uid-a', displayName: '성주'),
        RoomMember(uid: 'uid-b', displayName: '민준'),
        RoomMember(uid: 'uid-c', displayName: '서연'),
      ],
    );

class _Page {
  final api = FakeChatApi()..detailToReturn = _room();
  final socket = FakeChatSocket();
  final ticks = StreamController<void>.broadcast();
  DateTime now = DateTime(2026, 10, 18, 12);
  Object? positionError;

  Future<void> pump(WidgetTester tester) async {
    addTearDown(() {
      ticks.close();
      socket.dispose();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
        chatSocketProvider.overrideWithValue(socket),
        currentUidProvider.overrideWithValue('uid-a'),
        locationShareTickerProvider.overrideWithValue(() => ticks.stream),
        locationShareReaderProvider.overrideWithValue(() async {
          final e = positionError;
          if (e != null) throw e;
          return const LatLng(35.68, 139.76);
        }),
        locationShareClockProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: Scaffold(body: LocationSharePage(roomId: 7))),
    ));
    await tester.pumpAndSettle();
  }

  Set<Marker> markers(WidgetTester tester) =>
      tester.widget<BaseGoogleMap>(find.byType(BaseGoogleMap)).markers;
}

void main() {
  setUpAll(() {
    GoogleMapsFlutterPlatform.instance = _FakeGoogleMapsFlutterPlatform();
  });

  testWidgets('그룹원을 이름으로 보여주고, 공유는 꺼진 채로 시작한다', (tester) async {
    await _Page().pump(tester);

    expect(find.text('그룹원 3'), findsOneWidget);
    expect(find.text('민준'), findsOneWidget);
    expect(find.text('서연'), findsOneWidget);
    expect(find.text('내 위치 공유 OFF'), findsOneWidget);
    expect(find.text('꺼짐'), findsNWidgets(3));
  });

  testWidgets('토글을 누르면 내 위치를 보내고 내 마커를 그린다', (tester) async {
    final page = _Page();
    await page.pump(tester);

    await tester.tap(find.byKey(const Key('locationShareToggle')));
    await tester.pumpAndSettle();

    expect(find.text('내 위치 공유 ON'), findsOneWidget);
    expect(page.socket.sent.where((s) => s.destination == '/app/location'), hasLength(1));
    expect(page.markers(tester).map((m) => m.markerId.value), ['me']);
  });

  testWidgets('그룹원의 위치가 오면 마커를 그리고, 소식이 끊기면 꺼짐으로 바꾼다', (tester) async {
    final page = _Page();
    await page.pump(tester);

    page.socket.emit(_topic, {'uid': 'uid-b', 'lat': 35.7, 'lng': 139.8, 'ts': 1});
    await tester.pumpAndSettle();

    final marker = page.markers(tester).single;
    expect(marker.markerId.value, 'uid-b');
    expect(marker.infoWindow.title, '민준');
    expect(marker.alpha, 1);
    expect(find.text('공유 중'), findsOneWidget);

    page.now = page.now.add(const Duration(seconds: 21));
    page.ticks.add(null);
    await tester.pumpAndSettle();

    expect(page.markers(tester).single.infoWindow.title, '민준 · 꺼짐');
    expect(page.markers(tester).single.alpha, lessThan(1));
    expect(find.text('공유 중'), findsNothing);
  });

  testWidgets('위치 권한이 없으면 켜지 않고 이유를 보여준다', (tester) async {
    final page = _Page()..positionError = const LocationPermissionDeniedException();
    await page.pump(tester);

    await tester.tap(find.byKey(const Key('locationShareToggle')));
    await tester.pumpAndSettle();

    expect(find.text('내 위치 공유 OFF'), findsOneWidget);
    expect(find.textContaining('위치 권한'), findsOneWidget);
  });

  testWidgets('멤버가 아닌 그룹이면 안내하고 위치를 구독하지 않는다', (tester) async {
    final page = _Page();
    page.api.roomDetailNotFound = true;
    await page.pump(tester);

    expect(find.textContaining('찾을 수 없어요'), findsOneWidget);
    expect(find.byType(BaseGoogleMap), findsNothing);
    expect(page.socket.activeSubscriptions, isEmpty);
  });

  testWidgets('폰 폭(360)에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = _Page()..positionError = const LocationServiceDisabledException();
    await page.pump(tester);

    await tester.tap(find.byKey(const Key('locationShareToggle')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
