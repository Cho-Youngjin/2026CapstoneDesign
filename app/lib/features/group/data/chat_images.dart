import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_api.dart';

/// 채팅에 보낼 사진을 갤러리에서 고른다(Plan D Task 6). 취소하면 null. 테스트는 가짜로 바꾼다.
///
/// 긴 변 1600px·품질 80으로 줄여 올린다 — 폰 사진 원본(5~10MB)은 서버 한도(5MB)를 넘기 쉽고, 채팅에서
/// 보기에는 이 정도로 충분하다. 대부분 1MB 이하가 된다.
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

/// 사진 메시지의 바이트(`imageUrl`로 받는다). 서버는 멤버에게만 주므로 로그인 토큰이 붙는 [ChatApi]로 받는다 —
/// `Image.network`에 토큰을 직접 넣으면 1시간 뒤 토큰이 만료됐을 때 새로 받을 방법이 없다.
///
/// 목록을 스크롤해 같은 사진이 다시 보일 때마다 받지 않도록, 받은 뒤 5분 동안은 아무도 보지 않아도 들고 있는다.
/// `retry`를 끈다: 실패하면 자동으로 여러 번 다시 받지 않고, 화면의 사진 자리를 눌러 다시 받게 한다.
final chatImageBytesProvider = FutureProvider.autoDispose.family<Uint8List, String>(
  (ref, imageUrl) async {
    final bytes = await ref.watch(chatApiProvider).imageBytes(imageUrl);
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 5), link.close);
    ref.onDispose(timer.cancel);
    return bytes;
  },
  retry: (_, _) => null,
);
