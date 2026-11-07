import 'dart:convert';

import 'mark.dart';
import 'recorder_status.dart';

// 화면(main isolate)과 기록 서비스(task isolate) 사이 메시지. 플러그인 포트로는 문자열·Map·List만
// 그대로 보낼 수 있어 JSON 문자열로 주고받고, 'type'으로 종류를 가른다.

String encodeMarkMessage(Mark mark) => jsonEncode({'type': 'mark', ...mark.toJson()});

Mark? decodeMarkMessage(Object data) {
  final json = _decode(data, 'mark');
  if (json == null) return null;
  try {
    return Mark.fromJson(json);
  } catch (_) {
    return null;
  }
}

String encodeStatusMessage(RecorderStatus status) =>
    jsonEncode({'type': 'status', ...status.toJson()});

RecorderStatus? decodeStatusMessage(Object data) {
  final json = _decode(data, 'status');
  if (json == null) return null;
  try {
    return RecorderStatus.fromJson(json);
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _decode(Object data, String type) {
  if (data is! String) return null;
  try {
    final json = jsonDecode(data);
    if (json is Map<String, Object?> && json['type'] == type) return json;
  } on FormatException {
    return null;
  }
  return null;
}
