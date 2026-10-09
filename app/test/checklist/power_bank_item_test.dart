import 'package:app/core/network/checklist_api.dart';
import 'package:app/features/checklist/data/power_bank_item.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistItem _item(int id, String category) =>
    ChecklistItem(id: id, category: category, title: 't$id', priority: id);

void main() {
  test('POWER 섹션의 마지막 항목 바로 뒤에 넣는다', () {
    final items = [_item(1, 'DOCUMENT'), _item(2, 'POWER'), _item(3, 'POWER'), _item(4, 'MONEY')];

    final result = withPowerBankItem(items, 100);

    expect(result.map((i) => i.id).toList(), [1, 2, 3, powerBankChecklistId, 4]);
    final bank = result[3];
    expect(bank.category, 'POWER');
    expect(bank.title, '보조배터리 기내 반입 (100Wh 이하)');
    expect(bank.description, '위탁 수하물 불가 · 기내 반입만 가능');
  });

  test('POWER 항목이 없으면 맨 끝에 붙여 새 섹션이 된다', () {
    final result = withPowerBankItem([_item(1, 'DOCUMENT')], 160);

    expect(result.map((i) => i.id).toList(), [1, powerBankChecklistId]);
    expect(result.last.title, '보조배터리 기내 반입 (160Wh 이하)');
  });

  test('한도 정보가 없으면 그대로 둔다', () {
    final items = [_item(1, 'POWER')];

    expect(withPowerBankItem(items, null), same(items));
  });
}
