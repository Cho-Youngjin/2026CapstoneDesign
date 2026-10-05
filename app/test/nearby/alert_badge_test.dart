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
}
