import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/wireframe_widgets.dart';
import 'data/trip_api.dart';
import 'data/trip_providers.dart';
import 'models/trip.dart';
import 'visa_page.dart' show tripErrorMessage;
import 'visa_result_display.dart';

final _shortDate = DateFormat('M/d');

/// 비자 판정 결과 화면(비자 탭에서 push되는 상세 화면).
///
/// 레이아웃은 와이어프레임("해외여행 발걸음 - 와이어프레임" Plan B)을 따르고,
/// 내용은 전부 [activeTripProvider]가 가져온 서버 판정 결과에서 나온다.
class VisaResultPage extends ConsumerWidget {
  const VisaResultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(activeTripProvider);
    final countryName = tripAsync.asData?.value?.countryNameKo;

    return Column(
      children: [
        _Header(title: countryName == null ? '판정 결과' : '$countryName 판정 결과'),
        Expanded(
          child: tripAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _CenteredNotice(
              message: tripErrorMessage(e),
              actionLabel: '다시 시도',
              onAction: () => ref.invalidate(activeTripProvider),
            ),
            data: (trip) => trip == null
                ? const _CenteredNotice(
                    message: '아직 저장한 여행 계획이 없습니다.\n비자 탭에서 일정을 입력해 주세요.',
                  )
                // 여행이 바뀌면 아래 화면의 로컬 상태(일정 완료 표시)를 새로 시작해야
                // 하므로 id를 key로 준다.
                : _ResultBody(key: ValueKey(trip.id), trip: trip),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

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
            child: Text(
              title,
              style: AppTextStyles.screenTitle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredNotice extends StatelessWidget {
  const _CenteredNotice({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

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
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 일정 완료 표시를 즉시 반영하기 위해 받은 여행을 로컬 상태로 들고 있는다.
/// 항목 하나를 체크할 때마다 전체를 다시 조회하지 않고, 서버가 돌려준 항목만
/// [Trip.replaceTask]로 갈아끼운다.
class _ResultBody extends ConsumerStatefulWidget {
  const _ResultBody({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends ConsumerState<_ResultBody> {
  late Trip _trip = widget.trip;
  bool _refreshing = false;

  Future<void> _markDone(TripTask task) async {
    if (task.done) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await ref.read(tripApiProvider).markTaskDone(_trip.id, task.id);
      if (mounted) setState(() => _trip = _trip.replaceTask(updated));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tripErrorMessage(e))));
    }
  }

  Future<void> _refreshJudgement() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _refreshing = true);
    try {
      final refreshed = await ref.read(tripApiProvider).refreshTrip(_trip.id);
      if (mounted) setState(() => _trip = refreshed);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tripErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visa = visaBadgeOf(_trip.visaResult);
    final passport = passportBadgeOf(_trip.visaResult);
    final tasks = [..._trip.tasks]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final doneCount = tasks.where((t) => t.done).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_trip.judgementStale) ...[
            _StaleBanner(
              busy: _refreshing,
              onRefresh: _refreshing ? null : _refreshJudgement,
            ),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _BadgeCard(badge: visa)),
              const SizedBox(width: 10),
              Expanded(child: _BadgeCard(badge: passport)),
            ],
          ),
          const SizedBox(height: 14),
          _BasisCard(trip: _trip),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('역산 일정', style: AppTextStyles.cardTitle),
              if (tasks.isNotEmpty)
                Text(
                  '$doneCount/${tasks.length} 완료',
                  style: AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            Text(
              '예정된 준비 일정이 없습니다.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            )
          else
            for (var i = 0; i < tasks.length; i++)
              _TimelineStep(
                task: tasks[i],
                departDate: _trip.departDate,
                isLast: i == tasks.length - 1,
                onTap: () => _markDone(tasks[i]),
              ),
          const SizedBox(height: 24),
          PillOutlineButton(
            label: '준비물 체크리스트 보기',
            onPressed: () => context.push(AppRoutes.checklist),
          ),
        ],
      ),
    );
  }
}

/// 여행을 만든 뒤 비자 판정 기준 데이터가 갱신됐을 때 뜨는 안내.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.busy, this.onRefresh});

  final bool busy;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return WireframeCard(
      color: AppColors.warnBg,
      borderColor: AppColors.warnBorder,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '판정 기준 데이터가 갱신됐습니다. 다시 판정해 주세요.',
              style: AppTextStyles.caption.copyWith(color: AppColors.warn),
            ),
          ),
          const SizedBox(width: 10),
          busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: onRefresh,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.warn,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('다시 판정', style: AppTextStyles.caption),
                ),
        ],
      ),
    );
  }
}

/// 비자/여권 판정 배지. 게이지는 비율로 말할 수 있을 때만 그린다.
class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final ResultBadge badge;

  static const _title = TextStyle(
    fontFamily: 'Noto Sans KR',
    fontWeight: FontWeight.w700,
    fontSize: 12,
  );

  ({Color bg, Color border, Color text}) get _palette => switch (badge.tone) {
        BadgeTone.info => (
            bg: AppColors.infoBg,
            border: AppColors.infoBorder,
            text: AppColors.accent,
          ),
        BadgeTone.warn => (
            bg: AppColors.warnBg,
            border: AppColors.warnBorder,
            text: AppColors.warn,
          ),
        BadgeTone.neutral => (
            bg: AppColors.stripeB,
            border: AppColors.borderMedium,
            text: AppColors.textTertiary,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final gauge = badge.gaugeFactor;

    return WireframeCard(
      color: palette.bg,
      borderColor: palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(badge.title, style: _title.copyWith(color: palette.text)),
          if (gauge != null) ...[
            const SizedBox(height: 7),
            // 바닥(전체 한도) 위에 채운 만큼을 겹쳐 그린다.
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                widthFactor: gauge,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.text,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            badge.caption,
            style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
          ),
        ],
      ),
    );
  }
}

/// 판정에 쓰인 값들을 그대로 보여준다 — 서버는 외교부 원문 문장을 돌려주지 않으므로
/// (`trip/VisaResultResponse.java`) 판정에 실제로 들어간 숫자만 적는다.
class _BasisCard extends StatelessWidget {
  const _BasisCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final result = trip.visaResult;
    final unverified = result.verdict == VisaVerdict.unverified;

    final lines = [
      '체류 ${result.stayDays}일 '
          '(${_shortDate.format(trip.departDate)} → ${_shortDate.format(trip.returnDate)})',
      result.visaFreeDays == null
          ? '무비자 허용 일수 미확인'
          : '무비자 허용 ${result.visaFreeDays}일',
      result.passportValidityMonths == null
          ? '여권 잔여기간 요건 없음'
          : '여권 잔여 유효기간 ${result.passportValidityMonths}개월 요건',
    ];

    return WireframeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('근거 (외교부 입국허가요건)', style: AppTextStyles.label),
              Text(
                unverified ? '자동 판정 불가' : '공공데이터 기준',
                style: AppTextStyles.caption.copyWith(
                  color: unverified ? AppColors.warn : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
              ),
            ),
        ],
      ),
    );
  }
}

/// 역산 일정 타임라인 한 단계: 좌측 점(+연결선), 우측 제목/상태/날짜.
/// 누르면 완료로 표시한다(서버는 완료 해제 API를 제공하지 않아 되돌릴 수 없다).
class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.task,
    required this.departDate,
    required this.isLast,
    required this.onTap,
  });

  final TripTask task;
  final DateTime departDate;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = taskToneOf(task, DateTime.now());
    final color = switch (tone) {
      TaskTone.done => AppColors.accent,
      TaskTone.urgent => AppColors.warn,
      TaskTone.upcoming => AppColors.placeholderPrimary,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                _TimelineDot(color: color, filled: tone != TaskTone.upcoming),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: AppColors.borderLight),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: InkWell(
                onTap: tone == TaskTone.done ? null : onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: AppTextStyles.body.copyWith(
                              color: tone == TaskTone.done
                                  ? AppColors.textSecondary
                                  : null,
                            ),
                          ),
                        ),
                        _StatusLabel(tone: tone, color: color),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      taskDateLabel(task, departDate: departDate),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.tone, required this.color});

  final TaskTone tone;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = switch (tone) {
      TaskTone.done => '완료',
      TaskTone.urgent => '지금 바로',
      TaskTone.upcoming => '예정',
    };
    return Text(text, style: AppTextStyles.caption.copyWith(color: color));
  }
}

/// 타임라인 점(dot) 스타일 — 완료/긴급은 채움, 예정은 테두리만.
class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.white,
        border: filled ? null : Border.all(color: color, width: 2),
      ),
    );
  }
}
