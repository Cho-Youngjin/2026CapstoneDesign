import '../data/wallet_database.dart';
import 'expense_category.dart';

/// 지갑 목록의 한 줄. 지출과 환전을 한 목록에서 날짜순으로 섞어 보여주기 위한 공통 모양.
sealed class WalletEntry {
  const WalletEntry();

  DateTime get date;
  int get id;
}

final class ExpenseEntry extends WalletEntry {
  const ExpenseEntry(this.row);

  final ExpenseRow row;

  @override
  DateTime get date => row.spentOn;

  @override
  int get id => row.id;
}

final class ExchangeEntry extends WalletEntry {
  const ExchangeEntry(this.row);

  final ExchangeRow row;

  @override
  DateTime get date => row.exchangedOn;

  @override
  int get id => row.id;
}

/// 목록에 그릴 순서로 합친다: 최근 날짜 먼저, 같은 날은 지출 다음 환전, 같은 종류는 나중 기록 먼저.
/// [filter]가 있으면 그 카테고리의 지출만 남기고 환전은 뺀다.
List<WalletEntry> buildWalletEntries({
  required List<ExpenseRow> expenses,
  required List<ExchangeRow> exchanges,
  ExpenseCategory? filter,
}) {
  final entries = <WalletEntry>[
    for (final e in expenses)
      if (filter == null || ExpenseCategory.fromCode(e.category) == filter) ExpenseEntry(e),
    if (filter == null)
      for (final x in exchanges) ExchangeEntry(x),
  ];
  entries.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final byType = _typeOrder(a).compareTo(_typeOrder(b));
    if (byType != 0) return byType;
    return b.id.compareTo(a.id);
  });
  return entries;
}

int _typeOrder(WalletEntry entry) => entry is ExpenseEntry ? 0 : 1;

/// 같은 날짜끼리 묶는다(날짜 머리글용). 입력 순서를 그대로 유지한다.
List<(DateTime, List<WalletEntry>)> groupByDate(List<WalletEntry> entries) {
  final groups = <(DateTime, List<WalletEntry>)>[];
  for (final entry in entries) {
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    if (groups.isNotEmpty && groups.last.$1 == day) {
      groups.last.$2.add(entry);
    } else {
      groups.add((day, [entry]));
    }
  }
  return groups;
}
