import 'package:footstep_core/footstep_core.dart';
import 'package:test/test.dart';

StepUpdate walked(int tMs, int sinceFix, [StepState state = StepState.walking]) =>
    StepUpdate(tMs: tMs, state: state, totalSteps: sinceFix, stepsSinceLastFix: sinceFix);

FixResult ok(int tMs) =>
    FixResult(tMs: tMs, fix: Fix(tMs: tMs, lat: 37.5, lng: 127.0, accuracyM: 5));

void main() {
  group('StepTriggerPolicy (단순 걸음 트리거 기준선)', () {
    PolicyContext at(int t) => PolicyContext(nowMs: t);

    test('시작하면 측위하고, 마지막 측위 뒤 67걸음(50m ÷ 0.75m)에 이르면 다시 측위한다', () {
      final p = StepTriggerPolicy();
      expect(p.onStart(at(0)), [const RequestFix()]);
      expect(p.onEvent(ok(1000), at(1000)), isEmpty);
      expect(p.onEvent(walked(30000, 66), at(30000)), isEmpty);
      expect(p.onEvent(walked(31000, 67), at(31000)), [const RequestFix()]);
    });

    test('응답을 기다리는 동안에는 걸음이 늘어도 다시 요청하지 않는다', () {
      final p = StepTriggerPolicy()..onStart(at(0));
      p.onEvent(ok(1000), at(1000));
      expect(p.onEvent(walked(31000, 70), at(31000)), [const RequestFix()]);
      expect(p.onEvent(walked(32000, 72), at(32000)), isEmpty);
      // 성공하면 감지기가 걸음을 0부터 다시 센다
      expect(p.onEvent(ok(33000), at(33000)), isEmpty);
      expect(p.onEvent(walked(34000, 3), at(34000)), isEmpty);
      expect(p.onEvent(walked(70000, 67), at(70000)), [const RequestFix()]);
    });

    test('실패하면 걸음을 67걸음 더 걸은 뒤 재시도한다(실패는 걸음 수를 되돌리지 않는다)', () {
      final p = StepTriggerPolicy()..onStart(at(0));
      p.onEvent(ok(1000), at(1000));
      expect(p.onEvent(walked(31000, 67), at(31000)), [const RequestFix()]);
      expect(p.onEvent(const FixResult(tMs: 61000), at(61000)), isEmpty);
      expect(p.onEvent(walked(62000, 68), at(62000)), isEmpty);
      expect(p.onEvent(walked(90000, 133), at(90000)), isEmpty);
      expect(p.onEvent(walked(91000, 134), at(91000)), [const RequestFix()]);
    });

    test('걸음이 없으면(버스·지하철·멈춤) 시간이 지나도 측위하지 않는다 — 탈것 판정이 없는 기준선', () {
      final p = StepTriggerPolicy()..onStart(at(0));
      p.onEvent(ok(1000), at(1000));
      expect(p.onEvent(walked(600000, 0, StepState.otherMotion), at(600000)), isEmpty);
      expect(p.onEvent(walked(1800000, 0, StepState.still), at(1800000)), isEmpty);
      expect(p.onEvent(const Wakeup(tMs: 1800000, tag: 'tick'), at(1800000)), isEmpty);
    });

    test('E가 작으면 더 자주 잰다', () {
      final p = StepTriggerPolicy(errorBudgetM: 25)..onStart(at(0));
      p.onEvent(ok(1000), at(1000));
      expect(p.stepsPerFix, 34);
      expect(p.onEvent(walked(20000, 34), at(20000)), [const RequestFix()]);
    });
  });
}
