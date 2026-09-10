import 'dart:async';

import 'package:app/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthInterceptor', () {
    test('토큰이 있으면 Authorization 헤더를 붙인다', () async {
      final interceptor = AuthInterceptor(() async => 'valid-token');
      final options = RequestOptions(path: '/api/countries');
      final handler = _CaptureRequestHandler();

      interceptor.onRequest(options, handler);
      await handler.done;

      expect(handler.captured!.headers['Authorization'], 'Bearer valid-token');
    });

    test('토큰이 없으면 헤더를 붙이지 않는다', () async {
      final interceptor = AuthInterceptor(() async => null);
      final options = RequestOptions(path: '/api/countries');
      final handler = _CaptureRequestHandler();

      interceptor.onRequest(options, handler);
      await handler.done;

      expect(handler.captured!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('resolveBaseUrl', () {
    test('안드로이드에서는 에뮬레이터 호스트 주소를 쓴다', () {
      expect(resolveBaseUrl(isAndroid: true), 'http://10.0.2.2:8080');
    });

    test('그 외에서는 localhost를 쓴다', () {
      expect(resolveBaseUrl(isAndroid: false), 'http://localhost:8080');
    });
  });
}

class _CaptureRequestHandler extends RequestInterceptorHandler {
  RequestOptions? captured;
  final _completer = Completer<void>();

  Future<void> get done => _completer.future;

  @override
  void next(RequestOptions requestOptions) {
    captured = requestOptions;
    _completer.complete();
  }
}
