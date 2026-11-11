import 'package:footstep_core/src/cli/key_values.dart';
import 'package:test/test.dart';

void main() {
  test('k=v 목록을 맵으로 바꾸고, 값에는 =가 더 있어도 된다', () {
    expect(parseKeyValues(['a=1', 'b=x=y', 'c=']), {'a': '1', 'b': 'x=y', 'c': ''});
  });

  test('=가 없거나 키가 비면 FormatException이다', () {
    expect(() => parseKeyValues(['abc']), throwsFormatException);
    expect(() => parseKeyValues(['=1']), throwsFormatException);
  });
}
