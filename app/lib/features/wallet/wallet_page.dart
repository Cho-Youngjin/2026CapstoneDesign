import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/wallet_database.dart';
import 'data/wallet_rate.dart';
import 'domain/currency_info.dart';
import 'domain/expense_category.dart';
import 'domain/wallet_entries.dart';
import 'domain/wallet_summary.dart';
import 'widgets/balance_card.dart';
import 'widgets/exchange_form_sheet.dart';
import 'widgets/expense_form_sheet.dart';
import 'widgets/rate_banner.dart';
import 'widgets/wallet_entry_list.dart';

/// 나라별 지갑(여행 가계부) 화면 — 지갑·환율 알림 설계 §5.2.
/// 준비물 탭의 `지갑` 카드에서 `/checklist/wallet?iso=JP`로 들어온다. 기록은 기기에만 저장한다.
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key, required this.isoAlpha2});

  final String isoAlpha2;

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  /// 카테고리 필터. null이면 전체(지출+환전).
  ExpenseCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(countryDetailProvider(widget.isoAlpha2));
    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Notice(title: '지갑', message: '국가 정보를 불러오지 못했습니다: $e'),
      data: (detail) {
        final code = detail.currencyCode?.trim();
        if (code == null || code.isEmpty) {
          return _Notice(
            title: '${detail.nameKo} 지갑',
            message: '이 나라의 통화 정보가 없어 지갑을 쓸 수 없습니다.',
          );
        }
        return _wallet(detail, currencyInfoOf(code));
      },
    );
  }

  Widget _wallet(CountryDetail detail, CurrencyInfo currency) {
    final iso = widget.isoAlpha2;
    final rate = ref.watch(walletRateProvider(currency.code)).value;
    final expenses = ref.watch(walletExpensesProvider(iso)).value ?? const <ExpenseRow>[];
    final exchanges = ref.watch(walletExchangesProvider(iso)).value ?? const <ExchangeRow>[];
    final summary = WalletSummary.of(expenses: expenses, exchanges: exchanges);
    final krwPerUnit = rate?.rate.krwRate;

    return Column(
      children: [
        _WalletHeader(title: '${detail.nameKo} 지갑', onClear: () => _clear(detail.nameKo)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(walletRateProvider(currency.code));
              await ref.read(walletRateProvider(currency.code).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                RateBanner(currency: currency, snapshot: rate),
                const SizedBox(height: 12),
                BalanceCard(currency: currency, summary: summary, krwPerUnit: krwPerUnit),
                const SizedBox(height: 14),
                _CategoryFilter(
                  currency: currency,
                  summary: summary,
                  selected: _filter,
                  onSelect: (c) => setState(() => _filter = c),
                ),
                WalletEntryList(
                  entries: buildWalletEntries(expenses: expenses, exchanges: exchanges, filter: _filter),
                  currency: currency,
                  currentKrwPerUnit: krwPerUnit,
                  onTapExpense: (row) => _editExpense(currency, row),
                  onTapExchange: (row) => _editExchange(currency, row),
                  onLongPressExpense: (row) => _deleteExpense(row),
                  onLongPressExchange: (row) => _deleteExchange(row),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: PillButton(
                  key: const Key('addExpenseButton'),
                  label: '지출 기록',
                  onPressed: () => _addExpense(currency),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillOutlineButton(
                  key: const Key('addExchangeButton'),
                  label: '환전 기록',
                  onPressed: () => _addExchange(currency),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  WalletDatabase get _db => ref.read(walletDatabaseProvider);

  /// 새 지출은 저장하는 순간의 환율로 원화 값을 고정한다(설계 §5.3). 폼을 연 동안 새 환율이
  /// 도착했을 수 있으므로, 폼이 닫힌 뒤에 다시 읽는다.
  Future<void> _addExpense(CurrencyInfo currency) async {
    final input = await showExpenseFormSheet(context, currency: currency);
    if (input == null || !mounted) return;
    final rateNow = ref.read(walletRateProvider(currency.code)).value;
    await _db.addExpense(
      isoAlpha2: widget.isoAlpha2,
      currencyCode: currency.code,
      category: input.category.code,
      amountMinor: input.amountMinor,
      krwPerUnitAtEntry: rateNow?.rate.krwRate,
      memo: input.memo,
      spentOn: input.spentOn,
    );
  }

  /// 수정해도 기록 시점 환율(krwPerUnitAtEntry)은 그대로 둔다.
  Future<void> _editExpense(CurrencyInfo currency, ExpenseRow row) async {
    final input = await showExpenseFormSheet(context, currency: currency, initial: row);
    if (input == null || !mounted) return;
    await _db.updateExpense(row.copyWith(
      category: input.category.code,
      amountMinor: input.amountMinor,
      memo: input.memo,
      spentOn: input.spentOn,
    ));
  }

  Future<void> _addExchange(CurrencyInfo currency) async {
    final input = await showExchangeFormSheet(context, currency: currency);
    if (input == null || !mounted) return;
    await _db.addExchange(
      isoAlpha2: widget.isoAlpha2,
      currencyCode: currency.code,
      amountMinor: input.amountMinor,
      krwPaid: input.krwPaid,
      memo: input.memo,
      exchangedOn: input.exchangedOn,
    );
  }

  Future<void> _editExchange(CurrencyInfo currency, ExchangeRow row) async {
    final input = await showExchangeFormSheet(context, currency: currency, initial: row);
    if (input == null || !mounted) return;
    await _db.updateExchange(row.copyWith(
      amountMinor: input.amountMinor,
      krwPaid: Value(input.krwPaid),
      memo: input.memo,
      exchangedOn: input.exchangedOn,
    ));
  }

  Future<void> _deleteExpense(ExpenseRow row) async {
    if (!await _confirm('기록 삭제', '이 지출 기록을 삭제할까요?') || !mounted) return;
    await _db.deleteExpense(row.id);
  }

  Future<void> _deleteExchange(ExchangeRow row) async {
    if (!await _confirm('기록 삭제', '이 환전 기록을 삭제할까요?') || !mounted) return;
    await _db.deleteExchange(row.id);
  }

  Future<void> _clear(String countryName) async {
    if (!await _confirm('지갑 비우기', '$countryName 지갑의 지출·환전 기록을 모두 지울까요? 되돌릴 수 없습니다.') ||
        !mounted) {
      return;
    }
    await _db.clearWallet(widget.isoAlpha2);
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('삭제')),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// 뒤로가기 + 제목 + 메뉴(지갑 비우기). 비자 결과 화면 헤더와 같은 모양이다.
class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.title, this.onClear});

  final String title;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textBody),
            onPressed: () => context.pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: AppTextStyles.screenTitle, overflow: TextOverflow.ellipsis),
          ),
          if (onClear != null)
            PopupMenuButton<String>(
              key: const Key('walletMenu'),
              icon: const Icon(Icons.more_vert, color: AppColors.textBody),
              onSelected: (_) => onClear!(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('지갑 비우기')),
              ],
            ),
        ],
      ),
    );
  }
}

/// 카테고리 필터(설계 §5.2-4). 각 칩에 그 카테고리의 지출 합계를 붙인다.
class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.currency,
    required this.summary,
    required this.selected,
    required this.onSelect,
  });

  final CurrencyInfo currency;
  final WalletSummary summary;
  final ExpenseCategory? selected;
  final ValueChanged<ExpenseCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterPill(
            key: const Key('filter_ALL'),
            label: '전체',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final c in ExpenseCategory.values) ...[
            const SizedBox(width: 8),
            FilterPill(
              key: Key('filter_${c.code}'),
              label: '${c.labelKo} ${currency.format(summary.spentByCategory[c]!)}',
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
          ],
        ],
      ),
    );
  }
}

/// 지갑을 쓸 수 없을 때의 안내(헤더 + 가운데 문구).
class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _WalletHeader(title: title),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(message, style: AppTextStyles.caption, textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}
