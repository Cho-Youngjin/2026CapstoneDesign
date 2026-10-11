import '../../../core/network/checklist_api.dart';

/// 여행 한 건의 준비물 항목(서버 `trip/TripChecklistItemResponse.java`). 국가 공통 준비물
/// [ChecklistItem]과 모양이 같고 체크 여부만 더 가진다 — 그래서 준비물 화면의 섹션 묶기와
/// 보조배터리 행 끼워 넣기(`withPowerBankItem`)를 그대로 쓴다.
class TripChecklistItem extends ChecklistItem {
  const TripChecklistItem({
    required super.id,
    required super.category,
    required super.title,
    super.description,
    required super.priority,
    required this.checked,
  });

  final bool checked;

  factory TripChecklistItem.fromJson(Map<String, dynamic> json) => TripChecklistItem(
        id: json['id'] as int,
        category: json['category'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        priority: json['priority'] as int,
        checked: json['checked'] as bool,
      );
}
