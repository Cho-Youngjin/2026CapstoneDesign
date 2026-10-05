import 'package:app/features/checklist/data/checklist_checked_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('토글하면 체크되고 다시 토글하면 해제된다', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChecklistCheckedStore(prefs);

    expect(store.checkedIds(isoAlpha2: 'VN'), isEmpty);

    await store.toggle(isoAlpha2: 'VN', templateId: 10);
    expect(store.checkedIds(isoAlpha2: 'VN'), {10});

    await store.toggle(isoAlpha2: 'VN', templateId: 10);
    expect(store.checkedIds(isoAlpha2: 'VN'), isEmpty);
  });

  test('나라마다 체크 상태가 분리된다', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ChecklistCheckedStore(prefs);

    await store.toggle(isoAlpha2: 'VN', templateId: 10);
    await store.toggle(isoAlpha2: 'JP', templateId: 10);

    expect(store.checkedIds(isoAlpha2: 'VN'), {10});
    expect(store.checkedIds(isoAlpha2: 'JP'), {10});

    await store.toggle(isoAlpha2: 'VN', templateId: 10);
    expect(store.checkedIds(isoAlpha2: 'VN'), isEmpty);
    expect(store.checkedIds(isoAlpha2: 'JP'), {10}); // 다른 나라에 영향 없음
  });

  test('재시작 후에도(SharedPreferences 유지) 상태가 남는다', () async {
    var prefs = await SharedPreferences.getInstance();
    await ChecklistCheckedStore(prefs).toggle(isoAlpha2: 'VN', templateId: 5);

    prefs = await SharedPreferences.getInstance(); // 새 인스턴스 = 재시작 시뮬레이션
    expect(ChecklistCheckedStore(prefs).checkedIds(isoAlpha2: 'VN'), {5});
  });
}
