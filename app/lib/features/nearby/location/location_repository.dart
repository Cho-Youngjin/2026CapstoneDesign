import 'package:geolocator/geolocator.dart';

class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException();
}

class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();
}

abstract class LocationRepository {
  Future<Position> getCurrentPosition();
}

class GeolocatorLocationRepository implements LocationRepository {
  @override
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationPermissionDeniedException();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException();
    }

    // timeLimit 없이는 fused location이 새 fix를 못 받을 때(에뮬레이터에서 특히 흔함)
    // Future가 영원히 끝나지 않는다 — 대기 화면이 무한정 멈추는 대신 타임아웃으로
    // 실패시켜 사용자가 재시도할 수 있게 한다.
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // 개발/테스트는 에뮬레이터로 진행 중 — .medium은 raw GPS를 켜지 않아
        // 에뮬레이터 주입 좌표가 전달되지 않는다. 실기기 배포 전 .medium으로 되돌릴 것.
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }
}
