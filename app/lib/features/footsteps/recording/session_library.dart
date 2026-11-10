import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'session_meta.dart';
import 'session_schema.dart';

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.directory,
    required this.sizeBytes,
    this.meta,
  });

  final String id;
  final Directory directory;
  final int sizeBytes;

  /// meta.json을 읽지 못하면(없음, 깨짐) null. 그래도 목록에서 빼지 않는다 — 데이터는 남아 있을 수 있다.
  final SessionMeta? meta;

  /// 정상 종료한 세션만 값이 있다.
  Duration? get duration {
    final m = meta;
    final ended = m?.endedAt;
    return m == null || ended == null ? null : ended.difference(m.startedAt);
  }
}

/// 기기에 쌓인 세션 폴더 목록과 zip 묶기.
class SessionLibrary {
  SessionLibrary(this._root);

  final Future<Directory> Function() _root;

  Future<List<SessionSummary>> list() async {
    final root = await _root();
    if (!await root.exists()) return const [];
    final summaries = <SessionSummary>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      var size = 0;
      await for (final file in entity.list(recursive: true)) {
        if (file is File) size += await file.length();
      }
      SessionMeta? meta;
      try {
        meta = await SessionMetaStore(File(p.join(entity.path, SessionSchema.metaFile))).read();
      } catch (_) {
        meta = null;
      }
      summaries.add(SessionSummary(
        id: p.basename(entity.path),
        directory: entity,
        sizeBytes: size,
        meta: meta,
      ));
    }
    // 폴더 이름이 시작 시각으로 시작하므로 이름 역순이 최신순이다.
    summaries.sort((a, b) => b.id.compareTo(a.id));
    return summaries;
  }

  Future<File> zip(SessionSummary session, Directory outDir) async {
    final zipPath = p.join(outDir.path, '${session.id}.zip');
    await ZipFileEncoder().zipDirectory(session.directory, filename: zipPath);
    return File(zipPath);
  }
}
