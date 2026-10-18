import 'package:app/features/nearby/widgets/nearby_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// 지도가 처음 만들어질 때 받은 설정과 마커를 기록한다(실제 플랫폼 뷰는 만들지 않는다).
class _CapturingMapsPlatform extends GoogleMapsFlutterPlatform {
  MapConfiguration? config;
  MapObjects? objects;

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    config = mapConfiguration;
    objects = mapObjects;
    return const SizedBox.shrink();
  }

  @override
  Future<void> init(int mapId) async {}
}

void main() {
  late _CapturingMapsPlatform platform;

  setUp(() {
    platform = _CapturingMapsPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
  });

  Future<void> pumpView(WidgetTester tester, {LatLng? overseasPosition}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: NearbyMapView(
              center: const LatLng(35.68, 139.76),
              places: const [],
              embassies: const [],
              overseasPosition: overseasPosition,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('해외 매핑 중이 아니면 실제 GPS 파란 점을 그대로 쓴다', (tester) async {
    await pumpView(tester);

    expect(platform.config?.myLocationEnabled, isTrue);
    final ids = platform.objects!.markers.map((m) => m.markerId.value);
    expect(ids, isNot(contains('overseas_current')));
    expect(find.byTooltip('해외 현재 위치'), findsNothing);
  });

  testWidgets('해외 매핑 중에는 실제 GPS(한국) 대신 해외 현재 위치를 표시한다', (tester) async {
    const overseas = LatLng(35.6812, 139.7671);
    await pumpView(tester, overseasPosition: overseas);

    // 기본 파란 점은 한국 위치라서 끈다.
    expect(platform.config?.myLocationEnabled, isFalse);
    final marker = platform.objects!.markers.singleWhere((m) => m.markerId.value == 'overseas_current');
    expect(marker.position, overseas);
    // 기본 "내 위치" 버튼은 한국으로 가므로 해외 위치로 가는 버튼이 따로 있다.
    expect(find.byTooltip('해외 현재 위치'), findsOneWidget);
  });
}
