import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCountryResolver implements CountryResolver {
  _FakeCountryResolver(this._mapping);
  final Map<String, String> _mapping; // 'lat,lng' -> iso2

  @override
  Future<String> resolveIso2(double lat, double lng) async {
    return _mapping['$lat,$lng'] ?? Checkin.unknownCountry;
  }
}

void main() {
  test('등록된 좌표는 매핑된 국가 코드를 반환한다', () async {
    final resolver = _FakeCountryResolver({'35.6,139.7': 'JP'});

    expect(await resolver.resolveIso2(35.6, 139.7), 'JP');
  });

  test('매핑에 없는 좌표는 미확인(XX)을 반환한다', () async {
    final resolver = _FakeCountryResolver({});

    expect(await resolver.resolveIso2(0, 0), Checkin.unknownCountry);
  });
}
