import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/checklist_api.dart';
import '../../core/network/country_detail_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import '../visa/data/trip_api.dart';
import '../visa/data/trip_list_providers.dart';
import '../visa/models/trip_checklist_item.dart';
import '../visa/models/trip_summary.dart';
import 'data/checklist_providers.dart';
import 'data/power_bank_item.dart';

/// 준비물 · 짐/서류 체크리스트 화면.
///
/// 나라를 직접 고르지 않고 "선택된 여행"의 체크리스트를 보여준다(여행계획 중심 설계 §3.3).
/// 목록과 체크 상태는 그 여행의 서버 체크리스트(`trip_checklist`)이고, 앱이 만드는 보조배터리
/// 행의 체크만 기기에 여행별로 저장한다.
class ChecklistPage extends ConsumerWidget {
  const ChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(tripListProvider);
    final selectedId = ref.watch(selectedTripIdProvider);

    return listAsync.when(
      loading: () => const Column(
        children: [
          _Header(),
          Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      ),
      error: (e, _) => Column(
        children: [
          const _Header(),
          Expanded(
            child: _CenteredMessage(
              message: '여행 목록을 불러오지 못했습니다.',
              actionLabel: '다시 시도',
              onAction: () => ref.invalidate(tripListProvider),
            ),
          ),
        ],
      ),
      data: (state) {
        final trip = resolveSelectedTrip(state.trips, selectedId, DateTime.now());
        if (trip == null) {
          return Column(
            children: [
              const _Header(),
              Expanded(
                child: _CenteredMessage(
                  message: '여행계획을 먼저 만들어 주세요.',
                  actionLabel: '여행계획 만들기',
                  actionKey: const Key('createTripButton'),
                  onAction: () => context.go(AppRoutes.visaNew),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _Header(trip: trip, onChangeTrip: () => _pickTrip(context, ref, state.trips)),
            if (state.offline) const _OfflineBanner(),
            // 여행이 바뀌면 낙관적 체크 상태를 새로 시작해야 하므로 id를 key로 준다.
            Expanded(child: _TripChecklistBody(key: ValueKey(trip.id), trip: trip)),
          ],
        );
      },
    );
  }

  Future<void> _pickTrip(BuildContext context, WidgetRef ref, List<TripSummary> trips) async {
    final picked = await showModalBottomSheet<TripSummary>(
      context: context,
      builder: (_) => _TripPickerSheet(trips: trips),
    );
    if (picked != null) await ref.read(selectedTripIdProvider.notifier).set(picked.id);
  }
}

class _TripChecklistBody extends ConsumerStatefulWidget {
  const _TripChecklistBody({super.key, required this.trip});

  final TripSummary trip;

  @override
  ConsumerState<_TripChecklistBody> createState() => _TripChecklistBodyState();
}

class _TripChecklistBodyState extends ConsumerState<_TripChecklistBody> {
  /// 서버 저장을 기다리지 않고 화면에 먼저 반영한 체크 상태. 저장이 실패하면 지운다(되돌림).
  final Map<int, bool> _optimistic = {};

  TripSummary get _trip => widget.trip;

  @override
  Widget build(BuildContext context) {
    final iso = _trip.countryIso2;
    final detailAsync = ref.watch(countryDetailProvider(iso));
    final checklistAsync = ref.watch(tripChecklistProvider(_trip.id));
    final powerBankChecked = ref.watch(powerBankCheckedProvider(_trip.id));

    bool isChecked(ChecklistItem item) {
      if (item.id == powerBankChecklistId) return powerBankChecked;
      return _optimistic[item.id] ?? (item is TripChecklistItem && item.checked);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          detailAsync.when(
            data: (detail) => _CountryInfoRow(
              detail: detail,
              onOpenWallet: () => context.push(AppRoutes.walletOf(_trip.id, iso)),
            ),
            loading: () => const _InfoLoading(),
            error: (e, _) => _InfoError('국가 정보를 불러오지 못했습니다: $e'),
          ),
          const SizedBox(height: 14),
          checklistAsync.when(
            data: (serverItems) {
              // 보조배터리는 상단 카드에서 체크리스트 행으로 옮겼다(지갑·환율 알림 설계 §5.1).
              final items = withPowerBankItem(serverItems, detailAsync.value?.powerBankWhLimit);
              final checkedCount = items.where(isChecked).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProgressCard(total: items.length, checked: checkedCount),
                  const SizedBox(height: 14),
                  ..._buildSections(items, isChecked),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _InfoError('준비물 목록을 불러오지 못했습니다.'),
                TextButton(
                  key: const Key('checklistRetry'),
                  onPressed: () => ref.invalidate(tripChecklistProvider(_trip.id)),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _AddManuallyRow(),
        ],
      ),
    );
  }

  /// 카테고리별로 묶어서 SectionLabel + 항목들을 순서대로 만든다.
  /// 서버가 priority 오름차순으로 이미 정렬해서 주므로, 처음 등장하는 순서 그대로
  /// 섹션을 나눈다. 환전(`MONEY`) 섹션 끝에는 환율 알림 설정으로 가는 행을 붙이고(지갑·환율 알림 설계 §6.1),
  /// 환전 섹션이 없는 나라면 목록 끝에 환전 섹션을 새로 만들어 그 행을 넣는다.
  List<Widget> _buildSections(List<ChecklistItem> items, bool Function(ChecklistItem) isChecked) {
    final widgets = <Widget>[];
    String? currentCategory;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.category != currentCategory) {
        currentCategory = item.category;
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
        widgets.add(SectionLabel(item.categoryLabelKo));
        widgets.add(const SizedBox(height: 4));
      }
      final checked = isChecked(item);
      widgets.add(_ChecklistRow(
        checked: checked,
        label: item.title,
        description: item.description,
        onTap: () => _toggle(item, checked),
      ));
      final lastOfMoney = item.category == _moneyCategory &&
          (i == items.length - 1 || items[i + 1].category != _moneyCategory);
      if (lastOfMoney) widgets.add(_RateAlertLink(onTap: _openRateAlert));
    }

    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('이 나라에 등록된 준비물이 아직 없습니다.'),
      ));
    }
    // 빈 목록 안내와 별개로, 환전 섹션이 없으면(빈 목록 포함) 끝에 만들어 환율 알림 진입 행을 둔다.
    if (!items.any((i) => i.category == _moneyCategory)) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
      widgets
        ..add(const SectionLabel('환전'))
        ..add(const SizedBox(height: 4))
        ..add(_RateAlertLink(onTap: _openRateAlert));
    }
    return widgets;
  }

  static const _moneyCategory = 'MONEY';

  void _openRateAlert() => context.push(AppRoutes.rateAlertOf(_trip.countryIso2));

  /// 보조배터리 행은 기기에 저장하고, 나머지는 화면에 먼저 반영한 뒤 서버에 저장한다.
  /// 서버 저장이 실패하면 화면을 되돌리고 알린다.
  Future<void> _toggle(ChecklistItem item, bool current) async {
    final next = !current;
    if (item.id == powerBankChecklistId) {
      await ref.read(powerBankCheckStoreProvider).setChecked(_trip.id, next);
      if (mounted) ref.invalidate(powerBankCheckedProvider(_trip.id));
      return;
    }
    setState(() => _optimistic[item.id] = next);
    try {
      await ref.read(tripApiProvider).checkItem(_trip.id, item.id, checked: next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimistic.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장하지 못했습니다. 다시 시도해 주세요.')),
      );
    }
  }
}

/// 상단 제목줄. 여행이 정해지면 나라·날짜와 [여행 바꾸기]를 보여준다.
class _Header extends StatelessWidget {
  const _Header({this.trip, this.onChangeTrip});

  final TripSummary? trip;
  final VoidCallback? onChangeTrip;

  @override
  Widget build(BuildContext context) {
    final trip = this.trip;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trip == null ? '준비물' : '준비물 · ${trip.countryNameKo}',
                  style: AppTextStyles.screenTitle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (trip != null) Text(trip.dateRangeLabel, style: AppTextStyles.caption),
              ],
            ),
          ),
          if (onChangeTrip != null)
            GestureDetector(
              key: const Key('changeTripButton'),
              onTap: onChangeTrip,
              child: Text(
                '여행 바꾸기',
                style: AppTextStyles.caption.copyWith(color: AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('offlineBanner'),
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Text('오프라인 · 마지막으로 불러온 목록', style: AppTextStyles.caption),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 20),
            TextButton(key: actionKey, onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// [여행 바꾸기] 시트. 나라가 아니라 내 여행 중에서 고른다.
class _TripPickerSheet extends StatelessWidget {
  const _TripPickerSheet({required this.trips});

  final List<TripSummary> trips;

  @override
  Widget build(BuildContext context) {
    final split = splitTrips(trips, DateTime.now());
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: ListView(
          children: [
            if (split.upcoming.isNotEmpty) ...[
              const _SheetSection('다가오는 여행'),
              for (final t in split.upcoming) _option(context, t),
            ],
            if (split.past.isNotEmpty) ...[
              const _SheetSection('지난 여행'),
              for (final t in split.past) _option(context, t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, TripSummary trip) => ListTile(
        key: Key('tripOption_${trip.id}'),
        title: Text(trip.countryNameKo),
        subtitle: Text(trip.dateRangeLabel),
        onTap: () => Navigator.of(context).pop(trip),
      );
}

class _SheetSection extends StatelessWidget {
  const _SheetSection(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: SectionLabel(text),
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

/// 환전 섹션 끝의 `환율 알림 ›` 행. 체크 항목이 아니라 설정 화면으로 가는 링크다.
class _RateAlertLink extends StatelessWidget {
  const _RateAlertLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('rateAlertLink'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerFaint)),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_none, size: 20, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('환율 알림', style: AppTextStyles.body.copyWith(color: AppColors.accent)),
                  const SizedBox(height: 2),
                  Text('등락 알림·목표 환율 도달 알림 설정', style: AppTextStyles.caption),
                ],
              ),
            ),
            Text('›', style: AppTextStyles.cardTitle.copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
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
