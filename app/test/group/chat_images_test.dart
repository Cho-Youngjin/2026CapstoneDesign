import 'dart:typed_data';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/features/group/data/chat_api.dart';
import 'package:app/features/group/data/chat_images.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_chat_api.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  group('ChatImageCache', () {
    test('한도를 넘으면 가장 오래 안 본 사진부터 버린다', () {
      final cache = ChatImageCache(maxBytes: 10);
      cache.put('a', _bytes(4));
      cache.put('b', _bytes(4));
      cache.get('a'); // a를 방금 봤다 → b가 가장 오래 안 본 것

      cache.put('c', _bytes(4));

      expect(cache.get('b'), isNull);
      expect(cache.get('a'), isNotNull);
      expect(cache.get('c'), isNotNull);
      expect(cache.totalBytes, 8);
    });

    test('한 장이 한도보다 크면 들고 있지 않는다', () {
      final cache = ChatImageCache(maxBytes: 10);

      cache.put('big', _bytes(11));

      expect(cache.get('big'), isNull);
      expect(cache.totalBytes, 0);
    });

    test('같은 주소를 다시 넣으면 크기를 한 번만 센다', () {
      final cache = ChatImageCache(maxBytes: 10);
      cache.put('a', _bytes(4));
      cache.put('a', _bytes(6));

      expect(cache.totalBytes, 6);
    });
  });

  test('화면에서 사라졌다가 다시 보여도 캐시에 있으면 다시 받지 않는다', () async {
    final api = FakeChatApi();
    final container = ProviderContainer(overrides: [
      chatApiProvider.overrideWithValue(api),
      currentUidProvider.overrideWithValue('uid-a'),
    ]);
    addTearDown(container.dispose);
    const url = '/api/rooms/1/images/5';

    final first = container.listen(chatImageBytesProvider(url), (_, _) {});
    await container.read(chatImageBytesProvider(url).future);
    first.close(); // 화면에서 사라짐 → provider는 버려진다
    await Future<void>.delayed(Duration.zero);

    final second = container.listen(chatImageBytesProvider(url), (_, _) {});
    addTearDown(second.close);
    await container.read(chatImageBytesProvider(url).future);

    expect(api.imageDownloads, [url]);
  });
}
