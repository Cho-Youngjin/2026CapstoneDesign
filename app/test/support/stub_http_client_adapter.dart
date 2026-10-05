import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 지정한 path로 오는 요청에 고정된 JSON 응답을 돌려준다.
/// 실제 네트워크를 타지 않고 API 클라이언트를 단위 테스트하기 위한 용도.
///
/// 사용법: `dio.httpClientAdapter = StubHttpClientAdapter(...)`.
/// 요청 path가 [path]를 포함하지 않으면 404를 돌려주므로, 잘못된 경로를
/// 호출하는 버그도 테스트에서 드러난다.
class StubHttpClientAdapter implements HttpClientAdapter {
  StubHttpClientAdapter({
    required this.path,
    required this.statusCode,
    required this.body,
  });

  final String path;
  final int statusCode;
  final String body;

  /// 마지막으로 받은 요청. 메서드·경로·바디 검증에 쓴다.
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (!options.path.contains(path)) {
      return ResponseBody.fromString(
        '{"error":"unexpected path ${options.path}"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
