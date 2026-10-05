import 'package:app/features/nearby/widgets/alert_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('1~4단계가 각각 다른 색과 라벨을 가진다', () {
    expect(alertColorForLevel(1), Colors.blue);
    expect(alertColorForLevel(2), Colors.yellow.shade800);
    expect(alertColorForLevel(3), Colors.orange);
    expect(alertColorForLevel(4), Colors.red);
    expect(alertLabelForLevel(1), '남색경보 (여행유의)');
    expect(alertLabelForLevel(4), '흑색경보 (여행금지)');
  });

  test('판정 불가(level 0)는 여행금지가 아니라 확인 필요로 표시한다', () {
    // 서버는 원문을 파싱하지 못했을 때 의도적으로 0을 내려준다. 이걸 기본 분기로
    // 흘려 '흑색경보 (여행금지)'라고 보여주면 없는 경보를 단정하는 셈이다.
    expect(alertLabelForLevel(0), '경보 확인 필요');
    expect(alertLabelForLevel(0), isNot(contains('여행금지')));
    expect(alertColorForLevel(0), isNot(Colors.red));
  });

  test('흑색경보 라벨은 level 4에만 쓴다', () {
    expect(alertLabelForLevel(4), '흑색경보 (여행금지)');
  });
}
