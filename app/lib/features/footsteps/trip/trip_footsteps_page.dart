import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footstep_core/footstep_core.dart' show Stay;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/wireframe_widgets.dart';
import '../../../router.dart';
import '../../visa/data/trip_list_providers.dart';
import '../map/base_google_map.dart';
import 'route_reconstruct_api.dart';
import 'trip_day.dart';
import 'trip_footsteps_providers.dart';
import 'trip_period.dart';
import 'trip_recording_permissions.dart';
import 'trip_recording_providers.dart';

final _chipDate = DateFormat('M/d');
final _clock = DateFormat('HH:mm');
final _steps = NumberFormat('#,###');

/// 국가 상세 지도와 같은 도시 단위 줌(country_detail_map_page.dart의 근거 참고).
const _dayZoom = 13.7;

/// 머문 시간 문구: `32분`, `1시간 5분`.
String stayDurationLabel(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return '$minutes분';
  return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
}

/// 이동 거리 문구: 1km 미만은 m, 넘으면 소수 한 자리 km.
String distanceLabel(double meters) =>
    meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(1)}km';

/// 머문 곳의 도착·출발 시각. 고른 날이 아닌 시각(밤을 넘긴 숙소)은 날짜를 붙인다.
String _stayClock(DateTime at, DateTime day) {
  final local = at.toLocal();
  final sameDay = local.year == day.year && local.month == day.month && local.day == day.day;
  return sameDay ? _clock.format(local) : '${_chipDate.format(local)} ${_clock.format(local)}';
}

/// 날짜별 보기(설계 2026-11-07 9-4, 여행 상세 → 발걸음). 출발일~귀국일 날짜 칩과, 고른 날의 복원 경로·머문 곳·걸음·이동
/// 거리를 보여 준다. 와이어프레임 확인 전이라 여행 상세의 머리글·pill 칩·카드 모양을 그대로 따른다.
class TripFootstepsPage extends ConsumerStatefulWidget {
  const TripFootstepsPage({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<TripFootstepsPage> createState() => _TripFootstepsPageState();
}

class _TripFootstepsPageState extends ConsumerState<TripFootstepsPage> with WidgetsBindingObserver {
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 설정에서 권한을 켜고 돌아오면 배너를 다시 확인하고, 그동안 기록 서비스가 쓴 점을 다시 읽는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(missingTripPermissionsProvider);
    ref.invalidate(tripRecordsProvider(widget.tripId));
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(tripListProvider);
    final summary = listAsync.asData?.value.trips.where((t) => t.id == widget.tripId).firstOrNull;
    final trip = summary == null ? null : TripPeriod.fromSummary(summary);

    return Column(
      children: [
        _Header(
          title: trip == null ? '발걸음' : '${trip.countryNameKo} 발걸음',
          caption: trip == null
              ? null
              : '${_chipDate.format(trip.departDate)} – ${_chipDate.format(trip.returnDate)}',
          onRefresh: () => ref.invalidate(tripRecordsProvider(widget.tripId)),
        ),
        const _PermissionBanner(),
        Expanded(
          child: trip == null
              ? Center(
                  child: listAsync.isLoading
                      ? const CircularProgressIndicator()
                      : Text('여행을 찾을 수 없어요', style: AppTextStyles.caption),
                )
              : ref.watch(tripRecordsProvider(widget.tripId)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('기록을 읽지 못했어요\n$e', textAlign: TextAlign.center)),
                    data: (records) {
                      final now = ref.watch(tripClockProvider)();
                      final selected = _selected ?? initialTripDate(trip, records.points, now);
                      final day = buildTripDay(selected, records.points, records.spans);
                      return Column(
                        children: [
                          _DateChips(
                            dates: tripDates(trip),
                            selected: selected,
                            onSelected: (date) => setState(() => _selected = date),
                          ),
                          Expanded(child: _DayView(tripId: widget.tripId, countryIso2: trip.countryIso2, day: day)),
                        ],
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.caption, required this.onRefresh});

  final String title;
  final String? caption;
  final VoidCallback onRefresh;

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
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.visa),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(title, style: AppTextStyles.screenTitle, overflow: TextOverflow.ellipsis)),
          if (caption != null) ...[
            const SizedBox(width: 8),
            Text(caption!, style: AppTextStyles.caption),
          ],
          const Spacer(),
          IconButton(
            key: const Key('tripFootstepsRefresh'),
            icon: const Icon(Icons.refresh, color: AppColors.textBody),
            tooltip: '다시 읽기',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

/// 권한(백그라운드 위치·활동 인식·알림)이 없으면 띄우는 배너(설계 9-4).
class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingTripPermissionsProvider).asData?.value ?? const <TripRecordingPermission>{};
    if (missing.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: WireframeCard(
        key: const Key('tripRecordingOffBanner'),
        color: AppColors.warnBg,
        borderColor: AppColors.warnBorder,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('기록이 꺼져 있어요', style: AppTextStyles.label.copyWith(color: AppColors.warn)),
                  const SizedBox(height: 4),
                  Text(
                    '권한이 없어요: ${[for (final p in TripRecordingPermission.values) if (missing.contains(p)) p.label].join(', ')}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textBody),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const Key('openRecordingSettings'),
              onPressed: () => ref.read(tripRecordingPermissionsProvider).openSettings(),
              style: TextButton.styleFrom(foregroundColor: AppColors.warn),
              child: Text('설정 열기', style: AppTextStyles.caption),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChips extends StatelessWidget {
  const _DateChips({required this.dates, required this.selected, required this.onSelected});

  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FilterPill(
          key: Key('tripDate_${DateFormat('yyyy-MM-dd').format(dates[i])}'),
          label: _chipDate.format(dates[i]),
          selected: dates[i] == selected,
          onTap: () => onSelected(dates[i]),
        ),
      ),
    );
  }
}

/// 고른 날의 지도와 요약.
class _DayView extends ConsumerWidget {
  const _DayView({required this.tripId, required this.countryIso2, required this.day});

  final int tripId;
  final String countryIso2;
  final TripDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (day.points.isEmpty) {
      return Center(child: Text('이 날의 발걸음 기록이 없어요', style: AppTextStyles.caption));
    }
    final request = DayRouteRequest(tripId: tripId, countryIso2: countryIso2, day: day);
    final route = ref.watch(dayRouteProvider(request)).asData?.value;
    final first = day.points.first;

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: BaseGoogleMap(
            // 날짜를 바꾸면 그날 첫 점으로 카메라를 새로 잡는다.
            key: ValueKey(day.date),
            initialCamera: CameraPosition(target: LatLng(first.lat, first.lng), zoom: _dayZoom),
            myLocationEnabled: false,
            polylines: {
              for (final (i, segment) in (route?.segments ?? const <RouteSegmentView>[]).indexed)
                Polyline(
                  polylineId: PolylineId('segment_$i'),
                  points: segment.coords,
                  color: segment.kind == RouteSegmentView.vehicle ? AppColors.warn : AppColors.accent,
                  width: 4,
                  patterns: segment.kind == RouteSegmentView.estimated
                      ? [PatternItem.dash(12), PatternItem.gap(8)]
                      : const [],
                ),
            },
            markers: {
              for (final (i, stay) in day.stays.indexed)
                Marker(
                  markerId: MarkerId('stay_$i'),
                  position: LatLng(stay.lat, stay.lng),
                  infoWindow: InfoWindow(title: _arrivalLabel(stay), snippet: _stayLabel(stay)),
                ),
            },
          ),
        ),
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (route != null && !route.roadMatched) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '도로 맞춤을 못 했어요 · 직선으로 이었어요',
                        key: const Key('roadMatchFailed'),
                        style: AppTextStyles.caption.copyWith(color: AppColors.warn),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(dayRouteProvider(request)),
                      child: Text('다시 시도', style: AppTextStyles.caption),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              WireframeCard(
                child: Row(
                  children: [
                    Expanded(child: _Stat(label: '걸음', value: _steps.format(day.steps))),
                    Expanded(
                      child: _Stat(label: '이동 거리', value: route == null ? '…' : distanceLabel(route.distanceMeters)),
                    ),
                    Expanded(child: _Stat(label: '머문 곳', value: '${day.stays.length}곳')),
                  ],
                ),
              ),
              for (final stay in day.stays)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('${_arrivalLabel(stay)} · ${_stayLabel(stay)}', style: AppTextStyles.body),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _arrivalLabel(Stay stay) =>
      '${_stayClock(DateTime.fromMillisecondsSinceEpoch(stay.arriveMs), day.date)} 도착';

  String _stayLabel(Stay stay) => '${stayDurationLabel(Duration(milliseconds: stay.durationMs))} 머묾';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.cardTitle),
      ],
    );
  }
}
