import 'dart:convert';

class TimelinePoint {
  const TimelinePoint({required this.lat, required this.lng, required this.timestamp});

  final double lat;
  final double lng;
  final DateTime timestamp;
}

/// Google Maps Timeline 내보내기(Takeout) JSON을 파싱한다.
/// 알 수 없는 필드나 깨진 항목은 건너뛰고, 파싱 가능한 좌표만 시간순으로 반환한다.
List<TimelinePoint> parseTimelineExport(String jsonContent) {
  final Map<String, dynamic> root;
  try {
    root = jsonDecode(jsonContent) as Map<String, dynamic>;
  } catch (_) {
    return [];
  }

  final segments = root['semanticSegments'];
  if (segments is! List) return [];

  final points = <TimelinePoint>[];
  for (final segment in segments) {
    if (segment is! Map<String, dynamic>) continue;
    final point = _extractPoint(segment);
    if (point != null) points.add(point);
  }

  points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return points;
}

TimelinePoint? _extractPoint(Map<String, dynamic> segment) {
  final startTimeRaw = segment['startTime'];
  if (startTimeRaw is! String) return null;

  final timestamp = DateTime.tryParse(startTimeRaw);
  if (timestamp == null) return null;

  final latLng = _findLatLng(segment);
  if (latLng == null) return null;

  return TimelinePoint(lat: latLng.$1, lng: latLng.$2, timestamp: timestamp.toUtc());
}

/// visit(장소 방문)과 activity(이동) 세그먼트 둘 다에서 "latLng" 형태의
/// "위도, 경도" 문자열을 찾는다. 어느 형태에도 없으면 null.
(double, double)? _findLatLng(Map<String, dynamic> segment) {
  final visit = segment['visit'];
  if (visit is Map<String, dynamic>) {
    final raw = visit['topCandidate']?['placeLocation']?['latLng'];
    final parsed = _parseLatLngString(raw);
    if (parsed != null) return parsed;
  }

  final activity = segment['activity'];
  if (activity is Map<String, dynamic>) {
    final raw = activity['start']?['latLng'];
    final parsed = _parseLatLngString(raw);
    if (parsed != null) return parsed;
  }

  return null;
}

(double, double)? _parseLatLngString(dynamic raw) {
  if (raw is! String) return null;
  final parts = raw.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  return (lat, lng);
}
