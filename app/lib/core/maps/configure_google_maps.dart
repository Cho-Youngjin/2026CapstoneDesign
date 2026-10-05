import 'dart:io' show Platform;

import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// GoogleMap 위젯을 화면에 두 개 이상 동시에 띄우면(해외 매핑 테스트의 좌/우
/// 분할 화면 등) Android 기본 렌더링 방식(Virtual Display)에서는 나중에 생성된
/// 지도의 타일이 비어 보이는 문제가 있다. `useAndroidViewSurface`를 켜면
/// AndroidViewSurface(하이브리드 컴포지션)로 바뀌어 각 지도가 독립적으로
/// 렌더링된다. main()에서 runApp 전에 한 번만 호출하면 된다.
void configureGoogleMapsRendering() {
  if (!Platform.isAndroid) return;

  final mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
  }
}
