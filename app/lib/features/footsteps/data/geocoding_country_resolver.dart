import 'package:geocoding/geocoding.dart';

import 'checkin.dart';
import 'country_resolver.dart';

class GeocodingCountryResolver implements CountryResolver {
  final _geocoding = Geocoding();

  @override
  Future<String> resolveIso2(double lat, double lng) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(lat, lng);
      final iso = placemarks.firstOrNull?.isoCountryCode;
      if (iso == null || iso.length != 2) return Checkin.unknownCountry;
      return iso.toUpperCase();
    } catch (_) {
      return Checkin.unknownCountry;
    }
  }
}

extension on List<Placemark> {
  Placemark? get firstOrNull => isEmpty ? null : first;
}
