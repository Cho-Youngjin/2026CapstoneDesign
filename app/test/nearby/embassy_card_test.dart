import 'package:app/features/nearby/models/embassy.dart';
import 'package:app/features/nearby/widgets/embassy_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, Embassy embassy) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EmbassyCard(embassy: embassy))),
    );
  }

  testWidgets('전화번호가 없는 공관은 전화 버튼이 눌리지 않는다', (tester) async {
    await pumpCard(
      tester,
      const Embassy(
        id: 'e2',
        type: '분관',
        name: '주호치민분관',
        lat: 10.78,
        lng: 106.70,
      ),
    );

    expect(find.textContaining('주호치민분관'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('번호가 있는 공관은 전화 버튼이 눌린다', (tester) async {
    await pumpCard(
      tester,
      const Embassy(
        id: 'e1',
        type: '대사관',
        name: '주베트남대한민국대사관',
        lat: 21.02,
        lng: 105.83,
        phone: '+84-24-xxx-xxxx',
        emergencyPhone: '+84-90-xxx-xxxx',
        address: '하노이',
      ),
    );

    expect(find.text('하노이'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
