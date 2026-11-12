import 'dart:convert';
import 'dart:io';

import 'package:footstep_core/src/cli/replay_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory session;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('replay_cli_test');
    session = Directory(p.join(root.path, 'mini-groundTruth'))..createSync();
    // 2분 동안 1초마다 같은 자리 GPS
    final rows = [for (var t = 0; t <= 120000; t += 1000) '$t,$t,37.5,127.0,5.0,0,0,30'];
    File(p.join(session.path, 'gps.csv')).writeAsStringSync(
        't_ms,fix_t_ms,lat,lng,accuracy_m,speed_mps,bearing_deg,altitude_m\n${rows.join('\n')}\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async => root.delete(recursive: true));

  test('필수 옵션이 없으면 사용법을 알리고 64를 돌려준다', () async {
    expect(await runReplayCli(const [], out: out, err: err), 64);
    expect(err.toString(), contains('사용법'));
  });

  test('모르는 정책이면 64를 돌려준다', () async {
    final code = await runReplayCli(
        ['--session', session.path, '--policy', 'nope', '--out', p.join(root.path, 'o')],
        out: out, err: err);
    expect(code, 64);
    expect(err.toString(), contains('알 수 없는 정책'));
  });

  test('세션 폴더가 없으면 66을 돌려준다', () async {
    final code = await runReplayCli(
        ['--session', p.join(root.path, 'missing'), '--policy', 'fixed_1m', '--out', p.join(root.path, 'o')],
        out: out, err: err);
    expect(code, 66);
  });

  test('재생해 결과 파일을 쓰고 한 줄 요약을 출력한다', () async {
    final outDir = p.join(root.path, 'out');
    final code = await runReplayCli(
        ['--session', session.path, '--policy', 'fixed_1m', '--out', outDir], out: out, err: err);

    expect(code, 0, reason: err.toString());
    expect(out.toString(), contains('fixed_1m fixes=3'));
    expect(out.toString(), contains('stays=0')); // 같은 자리 2분은 10분에 못 미친다
    expect(File(p.join(outDir, 'fixes.csv')).readAsLinesSync(), hasLength(4)); // 헤더 + 0·60·120초
    expect(File(p.join(outDir, 'actions.csv')).existsSync(), isTrue);
    expect(File(p.join(outDir, 'stays.csv')).readAsLinesSync(), ['arrive_ms,leave_ms,lat,lng,n_points']);
  });

  test('--stay-param이 머문 곳 묶기와 summary.json에 들어간다', () async {
    final outDir = p.join(root.path, 'out4');
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'fixed_1m',
      '--stay-param', 'min_stay_s=60', '--stay-param', 'use_still=false', '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    expect(File(p.join(outDir, 'stays.csv')).readAsLinesSync(),
        ['arrive_ms,leave_ms,lat,lng,n_points', '0,120000,37.5,127.0,3']);
    final summary =
        jsonDecode(File(p.join(outDir, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['stay_params'], {'radius_m': 100.0, 'min_stay_s': 60.0, 'use_still': false});
    expect(summary['stays'], 1);
  });

  test('--stay-param 형식이 틀리거나 모르는 키·잘못된 값이면 64를 돌려준다', () async {
    for (final bad in ['radius_m', 'radius=50', 'min_stay_s=0', 'use_still=maybe']) {
      final code = await runReplayCli([
        '--session', session.path, '--policy', 'fixed_1m', '--stay-param', bad, '--out', p.join(root.path, 'o'),
      ], out: StringBuffer(), err: err);
      expect(code, 64, reason: '--stay-param $bad');
    }
  });

  test('--param과 --ttff가 정책·재생 설정에 들어간다', () async {
    final outDir = p.join(root.path, 'out2');
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'time_speed', '--param', 'e_m=25',
      '--ttff', '5', '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    final summary =
        jsonDecode(File(p.join(outDir, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['policy_params'], {'e_m': 25.0});
    expect(summary['ttff_ms'], 5000);
  });

  test('--ttff가 NaN·Infinity·음수면 64를 돌려준다', () async {
    for (final bad in ['NaN', 'Infinity', '-1']) {
      final code = await runReplayCli([
        '--session', session.path, '--policy', 'fixed_1m', '--ttff', bad, '--out', p.join(root.path, 'o'),
      ], out: StringBuffer(), err: err);
      expect(code, 64, reason: '--ttff $bad');
    }
    expect(err.toString(), contains('--ttff'));
  });

  test('--param 형식이 틀리면 64를 돌려준다', () async {
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'time_speed', '--param', 'e_m', '--out', p.join(root.path, 'o'),
    ], out: out, err: err);
    expect(code, 64);
  });

  test('--detector와 --detector-param이 재생과 summary.json에 들어간다', () async {
    final outDir = p.join(root.path, 'out3');
    final code = await runReplayCli([
      '--session', session.path, '--policy', 'still_suppress', '--detector', 'adaptive',
      '--detector-param', 'n_confirm=6', '--out', outDir,
    ], out: out, err: err);

    expect(code, 0, reason: err.toString());
    final summary =
        jsonDecode(File(p.join(outDir, 'summary.json')).readAsStringSync()) as Map<String, Object?>;
    expect(summary['detector_id'], 'adaptive');
    expect((summary['detector_params'] as Map)['n_confirm'], 6);
  });

  test('--detector-param 형식이 틀리거나 모르는 파라미터면 64를 돌려준다', () async {
    for (final bad in ['n_confirm', 'nope=1']) {
      final code = await runReplayCli([
        '--session', session.path, '--policy', 'fixed_1m', '--detector', 'adaptive',
        '--detector-param', bad, '--out', p.join(root.path, 'o'),
      ], out: StringBuffer(), err: err);
      expect(code, 64, reason: '--detector-param $bad');
    }
  });
}
