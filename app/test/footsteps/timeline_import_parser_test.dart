import 'dart:io';

import 'package:app/features/footsteps/import/timeline_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visit과 activity 세그먼트에서 좌표를 추출한다', () {
    final json = File('test/fixtures/timeline_export_sample.json').readAsStringSync();

    final points = parseTimelineExport(json);

    expect(points, hasLength(2));
    expect(points[0].lat, closeTo(35.681236, 0.0001));
    expect(points[0].lng, closeTo(139.767125, 0.0001));
    expect(points[1].lat, closeTo(35.658034, 0.0001));
  });

  test('타임스탬프가 잘못된 세그먼트는 건너뛴다', () {
    final json = File('test/fixtures/timeline_export_sample.json').readAsStringSync();

    final points = parseTimelineExport(json);

    expect(points.any((p) => p.lat == 0 && p.lng == 0), isFalse);
  });

  test('완전히 형식이 다른 JSON을 줘도 예외 없이 빈 리스트를 반환한다', () {
    expect(parseTimelineExport('{"unrelated": true}'), isEmpty);
  });

  test('JSON 자체가 깨졌으면 빈 리스트를 반환한다', () {
    expect(parseTimelineExport('not json at all'), isEmpty);
  });
}
