import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_providers.dart';
import 'chat_api.dart';

/// 채팅에 보낼 사진을 갤러리에서 고른다(Plan D Task 6). 취소하면 null. 테스트는 가짜로 바꾼다.
///
/// 긴 변 1600px·품질 80으로 줄여 올린다 — 폰 사진 원본(5~10MB)은 서버 한도(5MB)를 넘기 쉽고, 채팅에서
/// 보기에는 이 정도로 충분하다. 대부분 1MB 이하가 된다.
///
/// 알려진 제약: 갤러리를 연 사이 메모리가 모자라 Android가 앱을 정리하면 고른 사진은 돌아오지 않는다
/// (`ImagePicker.retrieveLostData`로 되찾을 수는 있지만, 다시 켰을 때 어느 방에서 고른 사진인지까지 되살려야
/// 엉뚱한 방으로 보내지 않는다). 드문 경우라 다시 고르게 둔다.
final chatImagePickerProvider = Provider<Future<Uint8List?> Function()>((ref) {
  return () async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    return file?.readAsBytes();
  };
});

/// 받은 사진을 들고 있는 메모리 캐시. 목록을 스크롤해 같은 사진이 다시 보일 때마다 받지 않으려고 둔다.
/// 전체 크기가 [maxBytes]를 넘으면 가장 오래 안 본 사진부터 버린다 — 사진이 많은 대화를 빠르게 넘겨도
/// 메모리가 끝없이 늘지 않게. 앱이 올릴 때 줄이므로 사진 한 장은 대개 1MB 이하라 수십 장이 들어간다.
class ChatImageCache {
  ChatImageCache({this.maxBytes = 30 * 1024 * 1024});

  final int maxBytes;

  /// 넣은(또는 마지막으로 본) 순서. Dart의 기본 Map은 넣은 순서를 지키므로 앞쪽이 가장 오래 안 본 것이다.
  final Map<String, Uint8List> _entries = {};
  int _totalBytes = 0;

  int get totalBytes => _totalBytes;

  Uint8List? get(String imageUrl) {
    final bytes = _entries.remove(imageUrl);
    if (bytes != null) _entries[imageUrl] = bytes; // 방금 봤으니 맨 뒤로
    return bytes;
  }

  void put(String imageUrl, Uint8List bytes) {
    final old = _entries.remove(imageUrl);
    if (old != null) _totalBytes -= old.length;
    if (bytes.length > maxBytes) return; // 한 장이 한도보다 크면 들고 있지 않는다
    _entries[imageUrl] = bytes;
    _totalBytes += bytes.length;
    while (_totalBytes > maxBytes) {
      final oldest = _entries.keys.first;
      _totalBytes -= _entries.remove(oldest)!.length;
    }
  }
}

/// 앱 전체가 함께 쓰는 사진 캐시. 계정이 바뀌면 새로 만든다 — 이전 계정의 사진을 들고 있지 않게.
final chatImageCacheProvider = Provider<ChatImageCache>((ref) {
  ref.watch(currentUidProvider);
  return ChatImageCache();
});

/// 사진 메시지의 바이트(`imageUrl`로 받는다). 서버는 멤버에게만 주므로 로그인 토큰이 붙는 [ChatApi]로 받는다 —
/// `Image.network`에 토큰을 직접 넣으면 1시간 뒤 토큰이 만료됐을 때 새로 받을 방법이 없다.
///
/// 화면에서 사라지면 이 provider는 버려지고(autoDispose), 다시 보이면 [ChatImageCache]에서 꺼낸다.
/// `retry`를 끈다: 실패하면 자동으로 여러 번 다시 받지 않고, 화면의 사진 자리를 눌러 다시 받게 한다.
final chatImageBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, imageUrl) async {
    final cache = ref.watch(chatImageCacheProvider);
    final cached = cache.get(imageUrl);
    if (cached != null) return cached;
    final bytes = await ref.watch(chatApiProvider).imageBytes(imageUrl);
    cache.put(imageUrl, bytes);
    return bytes;
  },
  retry: (_, _) => null,
);
