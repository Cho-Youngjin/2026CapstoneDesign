import 'package:app/core/background/app_callback_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('작업 이름에 맞는 함수만 실행하고 그 결과를 돌려준다', () async {
    final ran = <String>[];
    final runners = <String, BackgroundTaskRunner>{
      'footstep': () async {
        ran.add('footstep');
        return true;
      },
      'rate': () async {
        ran.add('rate');
        return false;
      },
    };

    expect(await dispatchBackgroundTask('rate', runners), isFalse);
    expect(ran, ['rate']);
  });

  test('모르는 작업 이름은 아무것도 하지 않고 성공으로 끝낸다', () async {
    final ran = <String>[];

    final result = await dispatchBackgroundTask('old.task', {
      'footstep': () async {
        ran.add('footstep');
        return true;
      },
    });

    expect(result, isTrue);
    expect(ran, isEmpty);
  });
}
