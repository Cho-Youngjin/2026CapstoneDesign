import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/translate_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 네트워크 없이 고정 응답을 돌려주는 테스트용 어댑터.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
  RequestOptions? capturedRequest;
  Map<String, dynamic>? capturedBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
      ) async {
    capturedRequest = options;
    if (requestStream != null) {
      final bytes = await requestStream.expand((e) => e).toList();
      capturedBody = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    final payload = utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      payload,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  group('TranslateApi.translate', () {
    test('번역 결과를 파싱한다', () async {
      final adapter = _StubAdapter(200, {
        'translatedText': 'Hello',
        'detectedSourceLanguage': 'ko',
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      final result = await api.translate(text: '안녕하세요', targetLanguage: 'en');

      expect(result.translatedText, 'Hello');
      expect(result.detectedSourceLanguage, 'ko');
    });

    test('/api/translate로 텍스트와 대상 언어를 보낸다', () async {
      final adapter = _StubAdapter(200, {'translatedText': 'Bonjour'});
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      await api.translate(text: '안녕', targetLanguage: 'fr', sourceLanguage: 'ko');

      expect(adapter.capturedRequest!.path, '/api/translate');
      expect(adapter.capturedRequest!.method, 'POST');
      expect(adapter.capturedBody!['text'], '안녕');
      expect(adapter.capturedBody!['targetLanguage'], 'fr');
      expect(adapter.capturedBody!['sourceLanguage'], 'ko');
    });

    test('sourceLanguage를 생략하면 요청 본문에 넣지 않는다', () async {
      final adapter = _StubAdapter(200, {'translatedText': 'Hi'});
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      await api.translate(text: 'hi', targetLanguage: 'en');

      expect(adapter.capturedBody!.containsKey('sourceLanguage'), isFalse);
    });

    test('서버 오류(500)면 예외를 던진다', () async {
      final adapter = _StubAdapter(500, {'message': 'internal error'});
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = TranslateApi(dio);

      expect(
            () => api.translate(text: '안녕', targetLanguage: 'en'),
        throwsA(isA<DioException>()),
      );
    });
  });
}