abstract class CountryResolver {
  /// 좌표를 ISO-3166-1 alpha-2 국가 코드로 변환한다.
  /// 실패(오프라인, 바다 위 좌표 등)해도 예외를 던지지 않고 'XX'를 반환한다.
  Future<String> resolveIso2(double lat, double lng);
}
