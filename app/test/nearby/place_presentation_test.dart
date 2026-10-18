import 'package:app/features/nearby/models/place.dart';
import 'package:app/features/nearby/widgets/place_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDistance', () {
    test('1km 미만은 10m 단위로 올림하지 않고 가까운 10m로 맞춘다', () {
      expect(formatDistance(0), '10m 이내');
      expect(formatDistance(8), '10m 이내');
      expect(formatDistance(94), '90m');
      expect(formatDistance(996), '1.0km');
    });

    test('1km 이상은 소수 한 자리 km다', () {
      expect(formatDistance(1000), '1.0km');
      expect(formatDistance(1234), '1.2km');
      expect(formatDistance(7960), '8.0km');
    });
  });

  test('카테고리마다 서로 다른 색을 쓴다', () {
    final colors = {for (final c in PlaceCategory.values) c: c.color};
    expect(colors.values.toSet(), hasLength(PlaceCategory.values.length));
  });

  testWidgets('목록 항목에 카테고리 색 아이콘과 현재 위치로부터의 거리가 보인다', (tester) async {
    const place = Place(
      id: 'p1',
      name: '도쿄역',
      category: PlaceCategory.pharmacy,
      address: '도쿄',
      lat: 35.0,
      lng: 139.0,
      distanceMeters: 1234,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlaceListTile(place: place))),
    );

    expect(find.text('도쿄역'), findsOneWidget);
    expect(find.text('1.2km'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.color, PlaceCategory.pharmacy.color);
  });

  testWidgets('거리를 모르는 장소는 거리를 표시하지 않는다', (tester) async {
    const place = Place(
      id: 'p2',
      name: '어딘가',
      category: PlaceCategory.atm,
      address: '주소',
      lat: 35.0,
      lng: 139.0,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlaceListTile(place: place))),
    );

    expect(find.textContaining('km'), findsNothing);
    expect(find.textContaining('m'), findsNothing);
  });
}
