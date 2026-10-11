import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/prefs/shared_preferences_provider.dart';
import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/data/trip_deletion.dart';
import 'package:app/features/visa/data/trip_list_providers.dart';
import 'package:app/features/wallet/data/wallet_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_trip_api.dart';

Future<({ProviderContainer container, WalletDatabase db, SharedPreferences prefs})> _setUp(
    FakeTripApi api) async {
  SharedPreferences.setMockInitialValues({
    'selected_trip_id.uid-a': 7,
    'checklist_powerbank_7': true,
    'checklist_powerbank_8': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = WalletDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUidProvider.overrideWithValue('uid-a'),
    tripApiProvider.overrideWithValue(api),
    walletDatabaseProvider.overrideWithValue(db),
  ]);
  addTearDown(container.dispose);
  for (final tripId in [7, 8]) {
    await db.addExpense(tripId: tripId, currencyCode: 'VND', category: 'FOOD',
        amountMinor: 50000, spentOn: DateTime(2026, 12, 21));
  }
  return (container: container, db: db, prefs: prefs);
}

void main() {
  test('서버에서 지운 뒤 그 여행의 지갑·보조배터리 체크·선택을 정리한다', () async {
    final api = FakeTripApi();
    final s = await _setUp(api);
    expect(s.container.read(selectedTripIdProvider), 7);

    await s.container.read(tripDeleterProvider).delete(7);

    expect(api.deleteTripCalls, [7]);
    expect(await s.db.watchExpenses(7).first, isEmpty);
    expect(await s.db.watchExpenses(8).first, hasLength(1));
    expect(s.prefs.getBool('checklist_powerbank_7'), isNull);
    expect(s.prefs.getBool('checklist_powerbank_8'), isTrue);
    expect(s.container.read(selectedTripIdProvider), isNull);
  });

  test('선택된 여행이 아니면 선택은 그대로 둔다', () async {
    final s = await _setUp(FakeTripApi());

    await s.container.read(tripDeleterProvider).delete(8);

    expect(s.container.read(selectedTripIdProvider), 7);
  });

  test('서버 삭제가 실패하면 기기 쪽은 아무것도 지우지 않는다', () async {
    final s = await _setUp(FakeTripApi(deleteTripStatusCode: 500));

    await expectLater(s.container.read(tripDeleterProvider).delete(7), throwsA(anything));

    expect(await s.db.watchExpenses(7).first, hasLength(1));
    expect(s.prefs.getBool('checklist_powerbank_7'), isTrue);
    expect(s.container.read(selectedTripIdProvider), 7);
  });
}
