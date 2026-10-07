import 'package:app/features/translate/voice/speech_services.dart';
import 'package:flutter_test/flutter_test.dart';

/// speech_to_text 플러그인의 콜백은 "notListening 상태 → (잠시 뒤) 최종 결과" 순서로 올 수 있다.
/// 실기기(SM-S911N)에서 notListening이 최종 결과보다 약 2초 먼저 도착했고, 예전 코드는 그 신호로
/// 턴을 null로 끝내서 최종 결과가 버려졌다(번역 요청이 아예 나가지 않았다).
void main() {
  const grace = Duration(milliseconds: 200);

  group('SpeechTurn', () {
    test('notListening이 최종 결과보다 먼저 와도 늦게 온 최종 결과를 반환한다', () async {
      final turn = SpeechTurn(graceAfterStop: grace);

      turn.onResult('화장실이 어디예요', isFinal: false);
      turn.onStatus('notListening');
      turn.onStatus('done');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      turn.onResult('화장실이 어디예요', isFinal: true);

      expect(await turn.result, '화장실이 어디예요');
    });

    test('최종 결과가 끝내 안 오면 유예 뒤 마지막 부분 결과로 확정한다', () async {
      final turn = SpeechTurn(graceAfterStop: grace);

      turn.onResult('화장실이', isFinal: false);
      turn.onResult('화장실이 어디예요', isFinal: false);
      turn.onStatus('notListening');

      expect(await turn.result, '화장실이 어디예요');
    });

    test('최종 결과가 오면 유예를 기다리지 않고 바로 끝난다', () async {
      final turn = SpeechTurn(graceAfterStop: const Duration(seconds: 30));

      turn.onResult('안녕하세요', isFinal: true);

      expect(await turn.result.timeout(const Duration(milliseconds: 100)), '안녕하세요');
    });

    test('아무 말도 없어 doneNoResult가 오면 즉시 null로 끝난다', () async {
      final turn = SpeechTurn(graceAfterStop: const Duration(seconds: 30));

      turn.onStatus('notListening');
      turn.onStatus('doneNoResult');

      expect(await turn.result.timeout(const Duration(milliseconds: 100)), isNull);
    });

    test('말 없이 notListening만 오면 유예 뒤 null로 끝난다', () async {
      final turn = SpeechTurn(graceAfterStop: grace);

      turn.onStatus('notListening');

      expect(await turn.result, isNull);
    });

    test('에러가 오면 null로 끝난다', () async {
      final turn = SpeechTurn(graceAfterStop: const Duration(seconds: 30));

      turn.onError();

      expect(await turn.result.timeout(const Duration(milliseconds: 100)), isNull);
    });

    test('먼저 끝난 결과가 이후 신호에 덮어써지지 않는다', () async {
      final turn = SpeechTurn(graceAfterStop: grace);

      turn.onResult('첫 결과', isFinal: true);
      turn.onStatus('doneNoResult');
      turn.onError();
      turn.onResult('나중 결과', isFinal: true);

      expect(await turn.result, '첫 결과');
    });
  });
}
