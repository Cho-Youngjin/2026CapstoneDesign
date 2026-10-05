import 'package:app/features/nearby/location/location_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class _ThrowingLocationRepository implements LocationRepository {
  @override
  Future<Position> getCurrentPosition() {
    throw const LocationPermissionDeniedException();
  }
}

void main() {
  test('권한이 거부되면 LocationPermissionDeniedException을 던진다', () {
    final repository = _ThrowingLocationRepository();
    expect(
      () => repository.getCurrentPosition(),
      throwsA(isA<LocationPermissionDeniedException>()),
    );
  });
}
