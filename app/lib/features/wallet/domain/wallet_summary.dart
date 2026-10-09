import '../data/wallet_database.dart';
import 'currency_info.dart';
import 'expense_category.dart';

/// 지갑 화면 상단의 숫자들(설계 §5.2-3·4). 금액은 모두 현지 통화 최소단위.
class WalletSummary {
  const WalletSummary._({
    required this.exchangedMinor,
    required this.spentMinor,
    required this.spentByCategory,
    required this.exchangedWithPaidMinor,
    required this.krwPaidTotal,
  });

  factory WalletSummary.of({
    required List<ExpenseRow> expenses,
    required List<ExchangeRow> exchanges,
  }) {
    final byCategory = {for (final c in ExpenseCategory.values) c: 0};
    var spent = 0;
    for (final e in expenses) {
      spent += e.amountMinor;
      final category = ExpenseCategory.fromCode(e.category);
      byCategory[category] = byCategory[category]! + e.amountMinor;
    }
    var exchanged = 0;
    var withPaid = 0;
    var paid = 0;
    for (final x in exchanges) {
      exchanged += x.amountMinor;
      if (x.krwPaid != null) {
        withPaid += x.amountMinor;
        paid += x.krwPaid!;
      }
    }
    return WalletSummary._(
      exchangedMinor: exchanged,
      spentMinor: spent,
      spentByCategory: byCategory,
      exchangedWithPaidMinor: withPaid,
      krwPaidTotal: paid,
    );
  }

  final int exchangedMinor;
  final int spentMinor;

  /// 다섯 카테고리가 모두 키로 들어 있다(쓴 적 없으면 0).
  final Map<ExpenseCategory, int> spentByCategory;

  /// 낸 원화가 입력된 환전들의 현지 금액 합과, 그때 낸 원화 합. 평가손익 계산용.
  final int exchangedWithPaidMinor;
  final int krwPaidTotal;

  /// 남은 돈 = 환전 합계 − 지출 합계. 쓴 돈이 더 많으면 음수.
  int get balanceMinor => exchangedMinor - spentMinor;

  /// 평가손익(원) = 낸 원화가 입력된 환전분을 현재 환율로 바꾼 값 − 낸 원화.
  /// 그런 환전이 없거나 환율을 모르면 null.
  int? valuationGainKrw(CurrencyInfo currency, double? krwPerUnit) {
    if (krwPerUnit == null || exchangedWithPaidMinor == 0) return null;
    return currency.toKrw(exchangedWithPaidMinor, krwPerUnit) - krwPaidTotal;
  }
}
