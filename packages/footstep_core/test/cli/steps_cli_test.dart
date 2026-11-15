import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/src/cli/steps_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../detectors/synthetic.dart';

void main() {
  late Directory root;
  late Directory session;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('steps_cli_test');
    session = Directory(p.join(root.path, 'mini-groundTruth'))..createSync();
    final rows = [for (final r in walk(10)) '${r.tMs},${r.x},${r.y},${r.z}'];
    File(p.join(session.path, 'accel.csv')).writeAsStringSync('t_ms,x,y,z\n${rows.join('\n')}\n');
    File(p.join(session.path, 'marks.csv'))
        .writeAsStringSync('t_ms,kind,value\n0,count_start,\n9990,count_end,20\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async => root.delete(recursive: true));

  test('감지기를 돌려 결과 파일을 쓰고 한 줄 요약을 출력한다', () async {
    final outDir = p.join(root.path, 'out');
    final code = await runStepsCli(
        ['--session', session.path, '--detector', 'adaptive', '--out', outDir],
        out: out, err: err);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('adaptive steps='));
    expect(File(p.join(outDir, 'steps.csv')).readAsLinesSync().length, greaterThan(10));
    final summary =
        jsonDecode(File(p.join(outDir, 'step_summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect((summary['count_intervals'] as List).single['manual_steps'], 20);
  });

  test('--detector-param이 감지기에 들어간다', () async {
    final outDir = p.join(root.path, 'out2');
    final code = await runStepsCli([
      '--session', session.path, '--detector', 'adaptive', '--detector-param', 'n_confirm=6',
      '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    final summary =
        jsonDecode(File(p.join(outDir, 'step_summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect((summary['detector_params'] as Map)['n_confirm'], 6);
  });

  test('필수 옵션이 없거나, 모르는 감지기·틀린 파라미터면 64를 돌려준다', () async {
    expect(await runStepsCli(const [], out: out, err: err), 64);
    expect(err.toString(), contains('사용법'));
    for (final args in [
      ['--detector', 'nope'],
      ['--detector', 'adaptive', '--detector-param', 'n_confirm'],
      ['--detector', 'os', '--detector-param', 'n_confirm=6'],
    ]) {
      final code = await runStepsCli(
          ['--session', session.path, ...args, '--out', p.join(root.path, 'o')],
          out: StringBuffer(), err: StringBuffer());
      expect(code, 64, reason: args.join(' '));
    }
  });

  test('세션 폴더가 없으면 66, 기록이 없는 폴더면 65다', () async {
    expect(
        await runStepsCli([
          '--session', p.join(root.path, 'missing'), '--detector', 'os', '--out', p.join(root.path, 'o'),
        ], out: out, err: err),
        66);
    final empty = Directory(p.join(root.path, 'empty'))..createSync();
    expect(
        await runStepsCli(['--session', empty.path, '--detector', 'os', '--out', p.join(root.path, 'o')],
            out: out, err: err),
        65);
  });
}
