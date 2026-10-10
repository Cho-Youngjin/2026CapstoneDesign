import 'package:app/features/rate_alert/data/rate_alert_store.dart';
import 'package:app/features/rate_alert/domain/rate_alert_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late RateAlertStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = RateAlertStore(await SharedPreferences.getInstance());
  });

  final target = RateTarget(
    id: 7,
    unit: 100,
    targetKrw: 845,
    direction: TargetDirection.below,
    active: true,
    createdAt: DateTime(2026, 10, 11),
  );

  test('저장한 적 없는 통화는 빈 설정이다', () async {
    expect((await store.read('JPY')).isEnabled, isFalse);
    expect(await store.readAll(), isEmpty);
    expect(await store.anyEnabled(), isFalse);
  });

  test('통화별로 저장하고 다시 읽는다(코드는 대문자로 맞춘다)', () async {
    await store.save('jpy', RateAlertSettings(targets: [target]));
    await store.save('USD', const RateAlertSettings(daily: true));

    final jpy = await store.read('JPY');
    expect(jpy.targets.single.krwPerUnit, closeTo(8.45, 1e-9));
    expect((await store.read('usd')).daily, isTrue);
    expect((await store.readAll()).keys, containsAll(['JPY', 'USD']));
  });

  test('한 통화를 저장해도 다른 통화 설정은 그대로다', () async {
    await store.save('USD', const RateAlertSettings(daily: true));
    await store.save('JPY', RateAlertSettings(targets: [target]));
    await store.save('JPY', RateAlertSettings.empty);

    expect((await store.read('USD')).daily, isTrue);
    expect((await store.read('JPY')).targets, isEmpty);
  });

  test('켜진 알림이 하나라도 있는지 알려준다', () async {
    await store.save('JPY', RateAlertSettings(targets: [target.copyWith(active: false)]));
    expect(await store.anyEnabled(), isFalse);

    await store.save('USD', const RateAlertSettings(daily: true));
    expect(await store.anyEnabled(), isTrue);
  });

  test('깨진 값은 빈 설정으로 읽는다', () async {
    SharedPreferences.setMockInitialValues({RateAlertStore.key: '{not json'});
    store = RateAlertStore(await SharedPreferences.getInstance());

    expect(await store.readAll(), isEmpty);
  });
}
