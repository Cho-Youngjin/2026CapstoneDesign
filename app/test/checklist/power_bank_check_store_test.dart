import 'package:app/features/checklist/data/power_bank_check_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('여행별로 보조배터리 체크를 저장하고 지운다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PowerBankCheckStore(await SharedPreferences.getInstance());

    expect(store.isChecked(1), isFalse);

    await store.setChecked(1, true);
    expect(store.isChecked(1), isTrue);
    expect(store.isChecked(2), isFalse);

    await store.remove(1);
    expect(store.isChecked(1), isFalse);
  });
}
