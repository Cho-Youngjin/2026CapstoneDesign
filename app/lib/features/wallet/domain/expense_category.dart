/// 지출 카테고리 5종(지갑·환율 알림 설계 §5.3). DB에는 [code]를 문자열로 저장한다 —
/// enum 순서(index)로 저장하면 나중에 순서가 바뀔 때 기존 기록의 의미가 조용히 바뀐다.
enum ExpenseCategory {
  food('FOOD', '식비'),
  lodging('LODGING', '숙박'),
  transport('TRANSPORT', '교통'),
  sightseeing('SIGHTSEEING', '관광'),
  other('OTHER', '기타');

  const ExpenseCategory(this.code, this.labelKo);

  final String code;
  final String labelKo;

  /// 메모 입력란 힌트. 관광·기타는 무엇을 넣는 칸인지 예를 보여준다.
  String get memoHint {
    switch (this) {
      case ExpenseCategory.sightseeing:
        return '입장료, 투어 등';
      case ExpenseCategory.other:
        return '여행자보험, eSIM 등';
      default:
        return '메모 (선택)';
    }
  }

  /// 저장된 코드로 카테고리를 찾는다. 모르는 코드는 기타로 본다(기록을 숨기지 않기 위해).
  static ExpenseCategory fromCode(String code) =>
      values.firstWhere((c) => c.code == code, orElse: () => ExpenseCategory.other);
}
