import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/api_client.dart';
import '../data/overseas_mapping_api.dart';
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
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    state = const OverseasMappingState();
    ref.read(overseasMappingActiveProvider.notifier).state = false;
    ref.read(overseasPositionProvider.notifier).state = null;
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
    await _trySnap();
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
      _segmentBuffer
        ..clear()
        ..add(krPoints.last);
      _segmentDistance = 0;
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
    }
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
