import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';

typedef TokenSupplier = Future<String?> Function();

/// 매 요청마다 Firebase ID Token을 Authorization 헤더에 붙인다.
/// 토큰은 만료되므로 캐시하지 않고 매번 가져온다 (SDK가 내부적으로 캐시한다).
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokenSupplier);

  final TokenSupplier _tokenSupplier;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _tokenSupplier().then((token) {
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }).catchError((_) {
      handler.next(options);
    });
  }
}

String resolveBaseUrl({required bool isAndroid}) =>
    isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';

final apiClientProvider = Provider<Dio>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  final dio = Dio(BaseOptions(
    // 웹에서는 dart:io의 Platform을 건드리기만 해도 런타임 에러가 나므로
    // (Unsupported operation: Platform._operatingSystem), kIsWeb으로 먼저 걸러낸다.
    baseUrl: resolveBaseUrl(isAndroid: !kIsWeb && Platform.isAndroid),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  dio.interceptors.add(AuthInterceptor(authRepository.currentIdToken));
  return dio;
});
