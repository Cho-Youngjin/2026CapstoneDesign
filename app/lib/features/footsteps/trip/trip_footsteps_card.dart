import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../../../router.dart';
import 'trip_period.dart';
import 'trip_recording_providers.dart';

final _shortDate = DateFormat('M/d');

/// 여행 기록의 지금 단계.
enum TripRecordingPhase { upcoming, recording, paused, ended }

/// 여행 상세 카드가 말할 단계. 기간·일시정지만 본다 — 권한 문제는 날짜별 보기의 배너가 알린다(설계 9-4).
TripRecordingPhase tripRecordingPhaseOf(TripPeriod trip, DateTime now, {required bool paused}) {
  if (!now.isBefore(trip.endsAt)) return TripRecordingPhase.ended;
  if (paused) return TripRecordingPhase.paused;
  return now.isBefore(trip.startsAt) ? TripRecordingPhase.upcoming : TripRecordingPhase.recording;
}

/// 여행 상세의 '발걸음 기록' 칸(설계 9-2의 3번, 9-4의 입구). 기록 상태와 [기록 일시정지·재개], [날짜별 발걸음]을 둔다.
/// 국내 여행 상세에는 이 칸만 있다(설계 9-1).
class TripFootstepsCard extends ConsumerStatefulWidget {
  const TripFootstepsCard({super.key, required this.trip});

  final TripPeriod trip;

  @override
  ConsumerState<TripFootstepsCard> createState() => _TripFootstepsCardState();
}

class _TripFootstepsCardState extends ConsumerState<TripFootstepsCard> {
  /// 일시정지·재개 요청이 끝나기를 기다리는 중. 그동안 버튼을 막아 요청이 겹치지 않게 한다.
  bool _busy = false;

  TripPeriod get trip => widget.trip;

  Future<void> _togglePaused(bool paused) async {
    setState(() => _busy = true);
    // 위젯이 사라진 뒤에도 쓸 수 있게 미리 꺼내 둔다.
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(pausedTripIdsProvider.notifier).setPaused(trip.tripId, !paused);
    } catch (e) {
      debugPrint('여행 기록 일시정지를 바꾸지 못했습니다: $e');
      messenger?.showSnackBar(const SnackBar(content: Text('기록 상태를 바꾸지 못했습니다. 다시 시도해 주세요.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(tripClockProvider)();
    final paused = ref.watch(pausedTripIdsProvider).contains(trip.tripId);
    final phase = tripRecordingPhaseOf(trip, now, paused: paused);
    final message = switch (phase) {
      TripRecordingPhase.upcoming => '출발일(${_shortDate.format(trip.departDate)}) 0시부터 발걸음을 기록해요.',
      TripRecordingPhase.recording => '여행 중이라 발걸음을 기록하고 있어요.',
      TripRecordingPhase.paused => '기록을 일시정지했어요.',
      TripRecordingPhase.ended => '귀국 다음 날 기록을 마쳤어요.',
    };

    return WireframeCard(
      key: const Key('tripFootstepsCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('발걸음 기록', style: AppTextStyles.cardTitle),
          const SizedBox(height: 6),
          Text(message, key: const Key('tripRecordingStatus'), style: AppTextStyles.body),
          if (phase != TripRecordingPhase.ended) ...[
            const SizedBox(height: 4),
            // 재부팅하면 자동으로 다시 켜지 않는다(설계 9-2) — 사용자 화면에 이 한계를 적는다.
            Text(
              '앱을 열면 기록이 켜져요. 휴대폰을 다시 켠 뒤에는 앱을 한 번 열어 주세요.',
              style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (phase != TripRecordingPhase.ended) ...[
                Expanded(
                  child: PillOutlineButton(
                    key: const Key('tripRecordingToggle'),
                    label: paused ? '기록 재개' : '기록 일시정지',
                    height: 44,
                    onPressed: _busy ? null : () => _togglePaused(paused),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: PillOutlineButton(
                  key: const Key('openTripFootsteps'),
                  label: '날짜별 발걸음',
                  height: 44,
                  onPressed: () => context.push(AppRoutes.tripFootstepsOf(trip.tripId)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
