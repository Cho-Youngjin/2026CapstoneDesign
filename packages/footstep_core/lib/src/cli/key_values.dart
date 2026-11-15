/// CLI의 `k=v` 목록을 맵으로 바꾼다. '='가 없거나 키가 비면 FormatException이다(값은 비어도 되고 '='를 더 담아도 된다).
Map<String, String> parseKeyValues(Iterable<String> pairs) {
  final result = <String, String>{};
  for (final pair in pairs) {
    final i = pair.indexOf('=');
    if (i <= 0) throw FormatException('k=v 형식이어야 합니다: $pair');
    result[pair.substring(0, i)] = pair.substring(i + 1);
  }
  return result;
}
