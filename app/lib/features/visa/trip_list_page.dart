import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import '../../router.dart';
import '../account/account_sheet.dart';
import 'data/trip_list_providers.dart';
import 'models/trip_summary.dart';
import 'visa_result_display.dart';

/// 여행 탭의 첫 화면 — 내 여행 목록(여행계획 중심 설계 §3.1).
/// 다가오는 여행과 지난 여행을 나눠 보여주고, 카드를 누르면 여행 상세로 간다.
class TripListPage extends ConsumerWidget {
  const TripListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(tripListProvider);
    void openNew() => context.push(AppRoutes.visaNew);

    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('여행 계획', style: AppTextStyles.screenTitle),
              Row(
                children: [
                  GestureDetector(
                    key: const Key('createTripButton'),
                    onTap: openNew,
                    child: Text(
                      '+ 새 여행계획',
                      style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('accountButton'),
                    icon: const Icon(Icons.person_outline, color: AppColors.textBody),
                    tooltip: '계정',
                    onPressed: () => showAccountSheet(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Message(
              text: '여행 목록을 불러오지 못했습니다.',
              actionLabel: '다시 시도',
              onAction: () => ref.invalidate(tripListProvider),
            ),
            data: (state) => RefreshIndicator(
              onRefresh: () async {
                try {
                  ref.invalidate(tripListProvider);
                  await ref.read(tripListProvider.future);
                } catch (_) {
                  // 캐시도 없이 실패하면 화면이 오류 상태로 바뀐다 — 여기서 따로 알릴 것은 없다.
                }
              },
              child: state.trips.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        _Message(
                          text: '첫 여행계획을 만들어 보세요',
                          actionLabel: '새 여행계획 만들기',
                          actionKey: const Key('emptyCreateTripButton'),
                          onAction: openNew,
                        ),
                      ],
                    )
                  : _TripListView(state: state),
            ),
          ),
        ),
      ],
    );
  }
}

class _TripListView extends StatelessWidget {
  const _TripListView({required this.state});

  final TripListState state;

  @override
  Widget build(BuildContext context) {
    final split = splitTrips(state.trips, DateTime.now());
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        if (state.offline) ...[
          Text('오프라인 · 마지막으로 불러온 목록', style: AppTextStyles.caption),
          const SizedBox(height: 12),
        ],
        if (split.upcoming.isNotEmpty) ...[
          const SectionLabel('다가오는 여행'),
          const SizedBox(height: 8),
          for (final t in split.upcoming) _TripCard(trip: t),
        ],
        if (split.upcoming.isNotEmpty && split.past.isNotEmpty) const SizedBox(height: 14),
        if (split.past.isNotEmpty) ...[
          const SectionLabel('지난 여행'),
          const SizedBox(height: 8),
          for (final t in split.past) _TripCard(trip: t),
        ],
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final TripSummary trip;

  Color _toneColor(BadgeTone tone) => switch (tone) {
        BadgeTone.info => AppColors.accent,
        BadgeTone.warn => AppColors.warn,
        BadgeTone.neutral => AppColors.textTertiary,
      };

  @override
  Widget build(BuildContext context) {
    final chip = verdictChipOf(trip.verdict);
    final color = _toneColor(chip.tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        key: Key('tripCard_${trip.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(AppRoutes.tripOf(trip.id)),
        child: WireframeCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.countryNameKo, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 2),
                    Text(trip.dateRangeLabel, style: AppTextStyles.caption),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(980),
                ),
                child: Text(chip.label, style: AppTextStyles.caption.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String text;
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
              text,
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
