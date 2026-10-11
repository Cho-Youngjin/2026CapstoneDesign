import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/checklist_api.dart';
import '../../core/network/country_api.dart';
import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import 'data/checklist_providers.dart';
import 'data/power_bank_item.dart';

/// 준비물 · 짐/서류 체크리스트 화면.
///
/// country_detail_api.dart(국가 상세/결제등급)와 checklist_api.dart(준비물 목록)를
/// 실제로 호출해서 화면을 채운다. 체크(완료) 상태는 서버에 저장하지 않고
/// 기기 로컬(SharedPreferences, ChecklistCheckedStore)에 나라별로 저장한다.
class ChecklistPage extends ConsumerStatefulWidget {
  const ChecklistPage({super.key});

  @override
  ConsumerState<ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends ConsumerState<ChecklistPage> {
  String _isoAlpha2 = 'VN';
  String _countryLabel = '베트남';

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(countryDetailProvider(_isoAlpha2));
    final checklistAsync = ref.watch(checklistProvider(_isoAlpha2));
    final checkedIds = ref.watch(checklistCheckedIdsProvider(_isoAlpha2));

    return Column(
      children: [
        _Header(countryLabel: _countryLabel, onChangeCountry: _pickCountry),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                detailAsync.when(
                  data: (detail) => _CountryInfoRow(
                    detail: detail,
                    onOpenWallet: () => context.push(AppRoutes.walletOf(_isoAlpha2)),
                  ),
                  loading: () => const _InfoLoading(),
                  error: (e, _) => _InfoError('국가 정보를 불러오지 못했습니다: $e'),
                ),
                const SizedBox(height: 14),
                checklistAsync.when(
                  data: (serverItems) {
                    // 보조배터리는 상단 카드에서 체크리스트 행으로 옮겼다(지갑·환율 알림 설계 §5.1).
                    final items = withPowerBankItem(
                        serverItems, detailAsync.value?.powerBankWhLimit);
                    final checkedCount =
                        items.where((i) => checkedIds.contains(i.id)).length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProgressCard(total: items.length, checked: checkedCount),
                        const SizedBox(height: 14),
                        ..._buildSections(items, checkedIds),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _InfoError('준비물 목록을 불러오지 못했습니다: $e'),
                ),
                const SizedBox(height: 14),
                const _AddManuallyRow(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 카테고리별로 묶어서 SectionLabel + 항목들을 순서대로 만든다.
  /// 서버가 priority 오름차순으로 이미 정렬해서 주므로, 처음 등장하는 순서 그대로
  /// 섹션을 나눈다.
  List<Widget> _buildSections(List<ChecklistItem> items, Set<int> checkedIds) {
    final widgets = <Widget>[];
    String? currentCategory;

    for (final item in items) {
      if (item.category != currentCategory) {
        currentCategory = item.category;
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
        widgets.add(SectionLabel(item.categoryLabelKo));
        widgets.add(const SizedBox(height: 4));
      }
      widgets.add(_ChecklistRow(
        checked: checkedIds.contains(item.id),
        label: item.title,
        description: item.description,
        onTap: () => _toggleChecked(item.id),
      ));
    }

    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('이 나라에 등록된 준비물이 아직 없습니다.'),
      ));
    }
    return widgets;
  }

  /// 체크 상태를 기기 로컬에 저장하고, 저장이 끝나면 화면을 다시 그린다.
  void _toggleChecked(int templateId) {
    final isoAlpha2 = _isoAlpha2;
    ref
        .read(checklistCheckedStoreProvider)
        .toggle(isoAlpha2: isoAlpha2, templateId: templateId)
        .then((_) {
      if (mounted) {
        ref.invalidate(checklistCheckedIdsProvider(isoAlpha2));
      }
    });
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<Country>(
      context: context,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 360,
          child: Consumer(
            builder: (context, ref, _) {
              final countries = ref.watch(countryListProvider);
              return countries.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('국가 목록을 불러오지 못했습니다\n$e',
                        textAlign: TextAlign.center),
                  ),
                ),
                data: (list) => ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => ListTile(
                    title: Text(list[i].nameKo),
                    subtitle: Text(list[i].nameEn ?? '-'),
                    trailing: Text('Tier ${list[i].tier}'),
                    onTap: () => Navigator.of(context).pop(list[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _isoAlpha2 = selected.isoAlpha2;
        _countryLabel = selected.nameKo;
        // 체크 상태는 나라별로 따로 저장되므로 여기서 지우지 않는다 —
        // 이 나라에서 전에 체크했던 게 있으면 그대로 불러와진다.
      });
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.countryLabel, required this.onChangeCountry});

  final String countryLabel;
  final VoidCallback onChangeCountry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('준비물 · $countryLabel', style: AppTextStyles.screenTitle),
          GestureDetector(
            onTap: onChangeCountry,
            child: Text(
              '국가 변경',
              style: AppTextStyles.caption.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLoading extends StatelessWidget {
  const _InfoLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 64,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _InfoError extends StatelessWidget {
  const _InfoError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message, style: AppTextStyles.caption),
    );
  }
}

class _CountryInfoRow extends StatelessWidget {
  const _CountryInfoRow({required this.detail, required this.onOpenWallet});

  final CountryDetail detail;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final plug = detail.plugTypes != null && detail.voltageV != null
        ? '${detail.plugTypes}형 ${detail.voltageV}V'
        : '정보 없음';
    final payment = detail.paymentTier?.labelKo ?? '정보 없음';
    final currency = detail.currencyCode?.trim();

    return Row(
      children: [
        Expanded(child: _CountryInfoCard(label: '플러그', value: plug)),
        const SizedBox(width: 8),
        Expanded(child: _CountryInfoCard(label: '결제', value: payment)),
        const SizedBox(width: 8),
        Expanded(
          child: _CountryInfoCard(
            key: const Key('walletCard'),
            label: '지갑',
            value: currency == null || currency.isEmpty ? '정보 없음' : '$currency ›',
            onTap: onOpenWallet,
          ),
        ),
      ],
    );
  }
}

class _CountryInfoCard extends StatelessWidget {
  const _CountryInfoCard({super.key, required this.label, required this.value, this.onTap});

  final String label;
  final String value;

  /// 있으면 카드를 누를 수 있다(지갑 카드). 누를 수 있는 카드는 값 글자를 파란색으로 보인다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.placeholderPrimary,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.caption),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: onTap == null ? AppColors.ink : AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.total, required this.checked});

  final int total;
  final int checked;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : checked / total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('진행률', style: AppTextStyles.chip),
              Text(
                '$checked / $total',
                style: const TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.placeholderSecondary,
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 완료/미완료 상태를 표현하는 실제 준비물 항목 행 (탭하면 토글).
class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.checked,
    required this.label,
    this.description,
    this.onTap,
  });

  final bool checked;
  final String label;
  final String? description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CheckboxSquare(checked: checked),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Noto Sans KR',
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      color: checked
                          ? AppColors.textTertiary
                          : AppColors.textBody,
                      decoration: checked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckboxSquare extends StatelessWidget {
  const _CheckboxSquare({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    if (!checked) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.placeholderPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(5),
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}

class _AddManuallyRow extends StatelessWidget {
  const _AddManuallyRow();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderMedium),
          borderRadius: BorderRadius.circular(980),
        ),
        child: Text(
          '+ 직접 추가',
          style: AppTextStyles.chip.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
