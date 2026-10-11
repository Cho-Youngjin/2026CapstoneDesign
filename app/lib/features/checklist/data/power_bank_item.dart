import '../../../core/network/checklist_api.dart';

/// 보조배터리 행의 예약 id. 서버 준비물 템플릿 id(양수)와 겹치지 않게 음수를 쓴다.
/// 체크 상태는 다른 준비물처럼 ChecklistCheckedStore에 이 id로 저장된다.
const int powerBankChecklistId = -1;

/// 국가 정보의 보조배터리 기내 반입 한도(Wh)를 체크리스트 행으로 만들어 끼워 넣는다(설계 §5.1).
/// 서버 준비물 템플릿에는 없는 항목이라 앱에서 만든다. `POWER` 섹션 맨 뒤에 넣고,
/// `POWER` 항목이 없으면 맨 끝에 붙여 새 섹션이 되게 한다. 한도 정보가 없으면 목록을 그대로 돌려준다.
List<ChecklistItem> withPowerBankItem(List<ChecklistItem> items, int? whLimit) {
  if (whLimit == null) return items;
  final item = ChecklistItem(
    id: powerBankChecklistId,
    category: 'POWER',
    title: '보조배터리 기내 반입 (${whLimit}Wh 이하)',
    description: '위탁 수하물 불가 · 기내 반입만 가능',
    priority: 0,
  );
  final lastPower = items.lastIndexWhere((i) => i.category == 'POWER');
  final result = [...items];
  if (lastPower == -1) {
    result.add(item);
  } else {
    result.insert(lastPower + 1, item);
  }
  return result;
}
