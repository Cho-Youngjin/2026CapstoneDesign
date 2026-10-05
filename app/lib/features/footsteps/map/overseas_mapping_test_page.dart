import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/network/api_client.dart';
import '../data/overseas_mapping_api.dart';
import 'base_google_map.dart';

/// 마지막 anchor 이후 누적 이동거리가 이 값을 넘을 때마다 해외 도로 매칭을
/// 시도한다(설계 문서 §4(3), 2026-09-29 고정값).
const _triggerDistanceMeters = 50.0;

/// 해외 매핑 테스트 화면(설계 문서 §9). 왼쪽엔 실제 국내 이동을, 오른쪽엔 그
/// 이동을 해외 도로망에 투영·매칭한 결과를 실시간으로 보여준다. 여기서 기록한
/// 경로는 실제 체크인/RoutePoint로 저장되지 않는 별도 테스트 세션이다.
class OverseasMappingTestPage extends ConsumerStatefulWidget {
  const OverseasMappingTestPage({
    super.key,
    required this.country,
    required this.initialAnchor,
  });

  final String country;
  final LatLng initialAnchor;

  @override
  ConsumerState<OverseasMappingTestPage> createState() => _OverseasMappingTestPageState();
}

class _OverseasMappingTestPageState extends ConsumerState<OverseasMappingTestPage> {
  StreamSubscription<Position>? _sub;
  GoogleMapController? _krMapController;
  GoogleMapController? _jpMapController;

  late LatLng _anchor = widget.initialAnchor;
  final List<LatLng> _krRoute = [];
  final List<LatLng> _jpRoute = [];
  // 서버가 요청 사이에 이어 달라고 돌려주는 값(진행 방향·지나온 길 등).
  Map<String, dynamic>? _walkState;

  // anchor 이후 아직 매칭에 반영되지 않은 국내 좌표. 첫 원소는 항상 이 구간이
  // 시작된 시점의 국내 좌표(walk_overseas_segment가 이동량을 재는 기준점)다.
  final List<LatLng> _segmentBuffer = [];
  double _segmentDistance = 0;
  bool _busy = false;

  // 해외 지도의 현재 위치점 + 진행 방향 화살표. 실제 GPS 파란 점은 국내 좌표라
  // 해외 지도에서는 끄고, 투영된 위치를 직접 마커로 그린다.
  BitmapDescriptor? _arrowIcon;
  double _jpHeading = 0;

  @override
  void initState() {
    super.initState();
    _buildArrowIcon().then((icon) {
      if (mounted) setState(() => _arrowIcon = icon);
    });
    _jpRoute.add(_anchor);
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen(_onPosition);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onPosition(Position position) async {
    final point = LatLng(position.latitude, position.longitude);

    setState(() {
      if (_krRoute.isNotEmpty) {
        _segmentDistance += Geolocator.distanceBetween(
          _krRoute.last.latitude,
          _krRoute.last.longitude,
          point.latitude,
          point.longitude,
        );
      }
      _krRoute.add(point);
      _segmentBuffer.add(point);
    });
    _krMapController?.animateCamera(CameraUpdate.newLatLng(point));

    if (_busy || _segmentBuffer.length < 2 || _segmentDistance < _triggerDistanceMeters) return;
    await _trySnap();
  }

  Future<void> _trySnap() async {
    setState(() => _busy = true);
    final krPoints = List<LatLng>.unmodifiable(_segmentBuffer);
    try {
      final result = await walkOverseasSegment(
        ref.read(apiClientProvider),
        country: widget.country,
        anchor: _anchor,
        krPoints: krPoints,
        state: _walkState,
      );
      if (!mounted) return;

      if (!result.ok) {
        // 카운터를 리셋하지 않고 다음 트리거에서 더 긴 구간으로 재시도한다 — 별도
        // 재시도 로직 없이 트리거 자체가 재시도를 겸한다.
        return;
      }

      setState(() {
        _jpRoute.addAll(result.matched);
        _walkState = result.state ?? _walkState;
        _anchor = result.newAnchor ?? _anchor;
        _jpHeading = _headingOf(result.matched) ?? _jpHeading;
        _segmentBuffer
          ..clear()
          ..add(krPoints.last);
        _segmentDistance = 0;
      });
      _jpMapController?.animateCamera(CameraUpdate.newLatLng(_anchor));
    } catch (_) {
      // 네트워크 실패 등은 매칭 실패와 동일하게 취급한다 — 다음 트리거에서 재시도.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('해외 매핑 테스트'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
            label: const Text('멈춤', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: BaseGoogleMap(
              initialCamera: CameraPosition(
                target: _krRoute.isEmpty ? const LatLng(37.5665, 126.9780) : _krRoute.first,
                zoom: 16,
              ),
              onMapCreated: (controller) => _krMapController = controller,
              polylines: {
                if (_krRoute.length > 1)
                  Polyline(
                    polylineId: const PolylineId('kr_route'),
                    points: _krRoute,
                    color: const Color(0xFF2563EB),
                    width: 4,
                  ),
              },
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: BaseGoogleMap(
              initialCamera: CameraPosition(target: widget.initialAnchor, zoom: 16),
              onMapCreated: (controller) => _jpMapController = controller,
              myLocationEnabled: false,
              markers: {
                Marker(markerId: const MarkerId('overseas_anchor_start'), position: widget.initialAnchor),
                if (_arrowIcon != null)
                  Marker(
                    markerId: const MarkerId('overseas_current'),
                    position: _anchor,
                    icon: _arrowIcon!,
                    rotation: _jpHeading,
                    flat: true,
                    anchor: const Offset(0.5, 0.5),
                    zIndexInt: 1,
                  ),
              },
              polylines: {
                if (_jpRoute.length > 1)
                  Polyline(
                    polylineId: const PolylineId('jp_route'),
                    points: _jpRoute,
                    color: const Color(0xFFEA580C),
                    width: 4,
                  ),
              },
            ),
          ),
        ],
      ),
    );
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

/// 파란 점 + 위쪽(북쪽)을 가리키는 화살표 아이콘. Marker.rotation으로 돌려 쓴다.
Future<BitmapDescriptor> _buildArrowIcon() async {
  const size = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(size / 2, size / 2);

  final arrow = Path()
    ..moveTo(size / 2, 4)
    ..lineTo(size / 2 + 16, 32)
    ..lineTo(size / 2 - 16, 32)
    ..close();
  canvas.drawPath(arrow, Paint()..color = const Color(0xFF2563EB));
  canvas.drawCircle(center, 22, Paint()..color = Colors.white);
  canvas.drawCircle(center, 17, Paint()..color = const Color(0xFF2563EB));

  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 36, height: 36);
}
