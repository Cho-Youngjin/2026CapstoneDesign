import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/api_client.dart';
import '../data/checkin.dart';
import '../data/overseas_mapping_api.dart';
import '../map/world_map_page.dart' show visitedCountriesProvider;
import 'footsteps_providers.dart';

/// 마지막 anchor 이후 누적 이동거리가 이 값을 넘을 때마다 해외 도로 매칭을
/// 시도한다(설계 문서 §4(3), 2026-09-29 고정값).
const overseasTriggerDistanceMeters = 50.0;

/// 해외 매핑 중 쓰는 위치 스트림. 테스트에서 가짜 스트림으로 바꿀 수 있게 provider로 뺀다.
final overseasMappingPositionStreamProvider = Provider<Stream<Position>>((ref) {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
  );
});

/// 화면이 그리는 해외 매핑 상태. 매핑이 끝나면 처음 상태로 돌아간다.
class OverseasMappingState {
  const OverseasMappingState({
    this.active = false,
    this.country = '',
    this.startAnchor,
    this.anchor,
    this.krRoute = const [],
    this.jpRoute = const [],
    this.jpHeading = 0,
  });

  final bool active;
  final String country;

  /// 사용자가 고른(도로에 붙인) 해외 출발점.
  final LatLng? startAnchor;

  /// 해외에서의 현재 위치(항상 도로 위).
  final LatLng? anchor;

  /// 한국에서의 실제 이동 경로(이 세션 동안만 화면 표시용으로 쌓는다).
  final List<LatLng> krRoute;

  /// 해외 도로 위에 투영된 경로.
  final List<LatLng> jpRoute;
  final double jpHeading;

  OverseasMappingState copyWith({
    LatLng? anchor,
    List<LatLng>? krRoute,
    List<LatLng>? jpRoute,
    double? jpHeading,
  }) =>
      OverseasMappingState(
        active: active,
        country: country,
        startAnchor: startAnchor,
        anchor: anchor ?? this.anchor,
        krRoute: krRoute ?? this.krRoute,
        jpRoute: jpRoute ?? this.jpRoute,
        jpHeading: jpHeading ?? this.jpHeading,
      );
}

/// 해외 매핑 세션. 화면(탭)과 무관하게 앱이 켜져 있는 동안 계속 돌아서, 다른 탭으로 가도
/// 한국 이동이 해외 도로 위 걸음으로 바뀌어 저장된다.
///
/// - 해외 경로는 RoutePoints(국가 = [OverseasMappingState.country])에 저장한다.
/// - 세션 동안 한국에서의 실제 이동은 저장하지 않는다([overseasMappingActiveProvider]).
/// - 주변 정보가 해외 현재 위치를 읽을 수 있게 [overseasPositionProvider]를 갱신한다.
final overseasMappingProvider =
    NotifierProvider<OverseasMappingNotifier, OverseasMappingState>(OverseasMappingNotifier.new);

class OverseasMappingNotifier extends Notifier<OverseasMappingState> {
  StreamSubscription<Position>? _sub;

  // 서버가 요청 사이에 이어 달라고 돌려주는 값(진행 방향·지나온 길 등).
  Map<String, dynamic>? _walkState;

  // anchor 이후 아직 매칭에 반영되지 않은 국내 좌표. 첫 원소는 항상 이 구간이
  // 시작된 시점의 국내 좌표(서버가 이동량을 재는 기준점)다.
  final List<LatLng> _segmentBuffer = [];
  double _segmentDistance = 0;
  bool _busy = false;

  // 지금 서버 응답을 기다리는 구간 요청. 멈출 때 이 요청이 끝날 때까지 기다려, 이미 걸은 구간을 버리지 않는다.
  Future<void>? _inFlight;
  bool _stopping = false;

  @override
  OverseasMappingState build() {
    ref.onDispose(() => _sub?.cancel());
    return const OverseasMappingState();
  }

  void start(String country, LatLng anchor) {
    if (state.active) return;
    _walkState = null;
    _segmentBuffer.clear();
    _segmentDistance = 0;
    _busy = false;

    state = OverseasMappingState(
      active: true,
      country: country,
      startAnchor: anchor,
      anchor: anchor,
      jpRoute: [anchor],
    );
    ref.read(overseasMappingActiveProvider.notifier).state = true;
    ref.read(overseasPositionProvider.notifier).state = anchor;
    _sub = ref.read(overseasMappingPositionStreamProvider).listen(_onPosition);
    // 시작 지점을 체크인으로 남겨, 이 나라가 방문 국가로 잡히고 이동 기록 목록을 볼 수 있게 한다.
    unawaited(_recordCheckin(country, anchor));
  }

  /// 해외 매핑을 멈춘다. 서버 응답을 기다리는 구간이 있으면 그 구간을 마저 저장한 뒤에 멈추고,
  /// 마지막 해외 위치를 체크인으로 남긴 다음 세계지도의 방문 국가 목록을 다시 읽게 한다.
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    try {
      _sub?.cancel();
      _sub = null;
      final pending = _inFlight;
      if (pending != null) await pending;
      // 기다리는 동안 들어와 남아 있는 좌표가 이미 기준 거리를 넘었다면, 다음 GPS를 기다리지 않고
      // 마지막으로 한 번 더 보낸다 — 멈추고 나면 그 구간을 보낼 기회가 없다.
      if (state.active &&
          _segmentBuffer.length >= 2 &&
          _segmentDistance >= overseasTriggerDistanceMeters) {
        await _trySnap();
      }

      // 마지막 해외 위치를 체크인으로 남겨 이번 해외 이동 기록의 끝을 표시한다.
      final wasActive = state.active;
      final country = state.country;
      final last = state.anchor;
      if (wasActive && last != null) await _recordCheckin(country, last);
      state = const OverseasMappingState();
      ref.read(overseasMappingActiveProvider.notifier).state = false;
      ref.read(overseasPositionProvider.notifier).state = null;
      // 세계지도의 방문 국가(와 그것을 보고 계산하는 추정 걸음 수)는 한 번 읽으면 캐시된다 —
      // 이번 세션에 처음 간 나라가 바로 보이도록 다시 읽게 한다.
      if (wasActive) ref.invalidate(visitedCountriesProvider);
    } finally {
      _stopping = false;
    }
  }

  Future<void> _onPosition(Position position) async {
    if (!state.active) return;
    final point = LatLng(position.latitude, position.longitude);

    final krRoute = state.krRoute;
    if (krRoute.isNotEmpty) {
      _segmentDistance += Geolocator.distanceBetween(
        krRoute.last.latitude,
        krRoute.last.longitude,
        point.latitude,
        point.longitude,
      );
    }
    _segmentBuffer.add(point);
    state = state.copyWith(krRoute: [...krRoute, point]);

    if (_busy || _segmentBuffer.length < 2 || _segmentDistance < overseasTriggerDistanceMeters) {
      return;
    }
    final snap = _trySnap();
    _inFlight = snap;
    await snap;
  }

  Future<void> _trySnap() async {
    _busy = true;
    final krPoints = List<LatLng>.unmodifiable(_segmentBuffer);
    try {
      final result = await walkOverseasSegment(
        ref.read(apiClientProvider),
        country: state.country,
        anchor: state.anchor!,
        krPoints: krPoints,
        state: _walkState,
      );
      if (!state.active) return;

      if (!result.ok) {
        // 카운터를 리셋하지 않고 다음 트리거에서 더 긴 구간으로 재시도한다 — 별도
        // 재시도 로직 없이 트리거 자체가 재시도를 겸한다.
        return;
      }

      // 직전 anchor와 같은 첫 점은 이미 저장돼 있으므로 건너뛴다(중복 방지).
      final jpRoute = state.jpRoute;
      final newPoints = [
        for (final p in result.matched)
          if (jpRoute.isEmpty || p != jpRoute.last) p,
      ];
      _walkState = result.state ?? _walkState;
      // 이번 요청에 보낸 앞부분만 덜어 낸다. 마지막 점은 다음 구간의 기준점으로 남기고, 응답을 기다리는
      // 동안 새로 들어온 좌표도 그대로 둔다(지우면 그만큼 걸은 길이 해외 경로에서 빠진다).
      _segmentBuffer.removeRange(0, math.min(krPoints.length - 1, _segmentBuffer.length));
      _segmentDistance = _pathLength(_segmentBuffer);
      final newAnchor = result.newAnchor ?? state.anchor!;
      state = state.copyWith(
        jpRoute: [...jpRoute, ...result.matched],
        anchor: newAnchor,
        jpHeading: _headingOf(result.matched) ?? state.jpHeading,
      );
      ref.read(overseasPositionProvider.notifier).state = newAnchor;

      await _persistOverseasPoints(state.country, newPoints);
    } catch (_) {
      // 네트워크 실패 등은 매칭 실패와 동일하게 취급한다 — 다음 트리거에서 재시도.
    } finally {
      _busy = false;
      _inFlight = null;
    }
  }

  // 체크인 저장 실패가 매핑 진행이나 종료를 막지 않도록 실패해도 조용히 넘긴다 — 이동 좌표(RoutePoints)는
  // 별도로 저장되고 있다. 시작할 때는 기다리지 않고, 멈출 때는 방문 국가 목록을 다시 읽기 전에 기다린다.
  Future<void> _recordCheckin(String country, LatLng at) {
    return ref
        .read(footstepsRepositoryProvider)
        .recordCheckinWithCountry(
          at.latitude,
          at.longitude,
          country,
          DateTime.now().toUtc(),
          CheckinSource.auto,
        )
        .catchError((_) {});
  }

  // 같은 시각에 쌓인 점들의 순서가 유지되도록 1ms씩 늘려 저장한다(경로는 recordedAt 순으로 읽는다).
  Future<void> _persistOverseasPoints(String country, List<LatLng> points) async {
    final repository = ref.read(footstepsRepositoryProvider);
    final base = DateTime.now().toUtc();
    for (var i = 0; i < points.length; i++) {
      await repository.recordRoutePoint(
        points[i].latitude,
        points[i].longitude,
        country,
        base.add(Duration(milliseconds: i)),
      );
    }
  }
}

double _pathLength(List<LatLng> path) {
  var total = 0.0;
  for (var i = 1; i < path.length; i++) {
    total += Geolocator.distanceBetween(
      path[i - 1].latitude,
      path[i - 1].longitude,
      path[i].latitude,
      path[i].longitude,
    );
  }
  return total;
}

/// 경로 끝의 서로 다른 두 점으로 진행 방향(북쪽 기준 시계 방향 도)을 구한다.
double? _headingOf(List<LatLng> path) {
  for (var i = path.length - 1; i > 0; i--) {
    if (path[i] != path[i - 1]) {
      return Geolocator.bearingBetween(
        path[i - 1].latitude,
        path[i - 1].longitude,
        path[i].latitude,
        path[i].longitude,
      );
    }
  }
  return null;
}
