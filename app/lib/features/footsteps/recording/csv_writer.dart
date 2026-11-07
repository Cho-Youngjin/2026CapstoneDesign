import 'dart:io';

/// 기록 세션의 CSV 파일 하나. 행을 메모리에 모았다가 [flush] 때 한 번에 쓴다 —
/// 50Hz 가속도를 행마다 디스크에 쓰면 쓰기 자체가 배터리를 써서 측정을 오염시킨다.
class CsvWriter {
  CsvWriter._(this.file, this._sink);

  final File file;
  final IOSink _sink;
  final StringBuffer _buffer = StringBuffer();
  int _pendingRows = 0;
  int _totalRows = 0;

  // IOSink는 flush가 끝나기 전에 다시 write/flush하면 StateError를 던진다. 서비스의 5초 tick과
  // 종료가 겹칠 수 있어 쓰기를 한 줄로 세운다.
  Future<void> _queue = Future.value();
  bool _closed = false;

  /// 파일이 없거나 비어 있으면 헤더를 쓴다. 내용이 있으면 이어 쓴다 — 시스템이 기록 서비스를
  /// 다시 띄워 같은 세션 폴더를 다시 열 때 헤더가 중간에 끼면 재생기가 읽지 못한다.
  static Future<CsvWriter> open(File file, List<String> header) async {
    await file.parent.create(recursive: true);
    final hasContent = await file.exists() && await file.length() > 0;
    final sink = file.openWrite(mode: FileMode.append);
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
    _buffer.writeln(row.map(formatCsvField).join(','));
    _pendingRows++;
    _totalRows++;
  }

  Future<void> flush() {
    if (_closed) return _queue;
    final chunk = _buffer.toString();
    _buffer.clear();
    _pendingRows = 0;
    return _queue = _queue.then((_) async {
      if (chunk.isNotEmpty) _sink.write(chunk);
      await _sink.flush();
    });
  }

  /// 여러 번 불러도 된다 — 기록 종료와 테스트 정리가 같은 파일을 두 번 닫을 수 있다.
  /// (Windows는 열린 파일이 있으면 폴더를 지우지 못해서 테스트가 항상 닫는다.)
  Future<void> close() async {
    if (_closed) return;
    final pending = flush();
    _closed = true;
    await pending;
    await _sink.close();
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
