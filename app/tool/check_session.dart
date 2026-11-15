import 'dart:io';

import 'package:app/features/footsteps/recording/session_check.dart';
import 'package:path/path.dart' as p;

/// 사용법(app/에서): dart run tool/check_session.dart <세션 폴더>
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('사용법: dart run tool/check_session.dart <세션 폴더>');
    exitCode = 64;
    return;
  }
  final dir = Directory(args.single);
  if (!await dir.exists()) {
    stderr.writeln('폴더가 없습니다: ${dir.path}');
    exitCode = 66;
    return;
  }
  stdout.writeln(formatSessionReport(await checkSession(dir)));
  final meta = File(p.join(dir.path, 'meta.json'));
  if (await meta.exists()) {
    stdout
      ..writeln('--- meta.json ---')
      ..writeln(await meta.readAsString());
  }
}
