import 'dart:io';

import 'package:flutter/foundation.dart';

/// 기록 세션의 CSV 파일 하나. 행을 메모리에 모았다가 [flush] 때 한 번에 쓴다 —
/// 50Hz 가속도를 행마다 디스크에 쓰면 쓰기 자체가 배터리를 써서 측정을 오염시킨다.
class CsvWriter {
  CsvWriter._(this.file, this._sink);

  final File file;
  final IOSink _sink;
  final StringBuffer _buffer = StringBuffer();
  int _pendingRows = 0;
  int _totalRows = 0;

  // 같은 IOSink에 flush/close가 겹치면 StateError가 난다(서비스의 5초 tick과 종료가 겹칠 수 있다).
  // 그래서 flush와 close를 전부 이 체인 위에 한 줄로 세운다.
  Future<void> _queue = Future.value();
  bool _closed = false;
  Future<void>? _closing;

  /// 파일이 없거나 비어 있으면 헤더를 쓴다. 내용이 있으면 이어 쓴다 — 시스템이 기록 서비스를
  /// 다시 띄워 같은 세션 폴더를 다시 열 때 헤더가 중간에 끼면 재생기가 읽지 못한다.
  ///
  /// [openSink]는 테스트가 쓰기 실패를 흉내 낼 때만 넘긴다. 보통은 기본 동작(파일 append)을 쓴다.
  @visibleForTesting
  static Future<CsvWriter> open(
    File file,
    List<String> header, {
    IOSink Function(File file)? openSink,
  }) async {
    await file.parent.create(recursive: true);
    final hasContent = await file.exists() && await file.length() > 0;
    final sink = openSink != null
        ? openSink(file)
        : file.openWrite(mode: FileMode.append);
    if (!hasContent) {
      sink.writeln(header.join(','));
      await sink.flush();
    }
    return CsvWriter._(file, sink);
  }

  /// 아직 디스크에 쓰지 않은 행 수.
  int get pendingRows => _pendingRows;

  /// 이 writer로 추가한 행 수(헤더 제외). 다시 열기 전에 쓴 행은 세지 않는다.
  int get totalRows => _totalRows;

  void add(List<Object?> row) {
    // 닫힌 뒤의 행은 던지지 않고 버린다 — 종료 중에 도착한 센서 이벤트 하나가 기록 서비스를
    // 죽이면 안 되고, 버린 행을 totalRows에 세면 기록 수가 실제보다 많아 보인다.
    if (_closed) return;
    _buffer.writeln(row.map(formatCsvField).join(','));
    _pendingRows++;
    _totalRows++;
  }

  Future<void> flush() {
    if (_closed) return _queue;
    final chunk = _buffer.toString();
    _buffer.clear();
    _pendingRows = 0;
    // 앞선 쓰기가 실패해도 이 쓰기는 실행한다 — 한 번의 디스크 오류 때문에 이후 기록이 전부
    // 막히면 안 된다. 실패는 이 flush를 돌려받은 쪽에 그대로 전달된다.
    return _queue = _queue.catchError((Object _) {}).then((_) async {
      if (chunk.isNotEmpty) _sink.write(chunk);
      await _sink.flush();
    });
  }

  /// 여러 번 불러도 된다 — 기록 종료와 테스트 정리가 같은 파일을 두 번 닫을 수 있다.
  /// 동시에 불러도 같은 future를 돌려준다. (Windows는 열린 파일이 있으면 폴더를 지우지
  /// 못해서 테스트가 항상 닫는다.)
  Future<void> close() => _closing ??= _closeOnce();

  Future<void> _closeOnce() async {
    final pending = flush();
    _closed = true;
    try {
      await pending;
    } finally {
      // 마지막 flush가 실패해도 핸들은 닫는다 — 닫지 않으면 파일 잠금이 남는다.
      await _sink.close();
    }
  }
}

/// CSV 필드 하나의 문자열. 값이 없거나 유한한 숫자가 아니면(NaN 등) 빈칸으로 둔다 —
/// 분석 쪽(pandas)이 빈칸을 결측치로 읽는다.
String formatCsvField(Object? value) {
  if (value == null) return '';
  if (value is double && !value.isFinite) return '';
  if (value is bool) return value ? '1' : '0';
  final text = value.toString();
  final needsQuote =
      text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r');
  return needsQuote ? '"${text.replaceAll('"', '""')}"' : text;
}
