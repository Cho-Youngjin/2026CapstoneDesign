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

/// `--dart-define=API_BASE_URL=http://<PC의 LAN IP>:8080` 로 실행하면 그 값을 그대로 쓴다
/// (실기기 테스트용 — 기기와 PC가 같은 Wi-Fi에 있어야 한다). 지정하지 않으면 기존 기본값
/// 그대로: 에뮬레이터는 10.0.2.2(호스트 PC를 가리키는 에뮬레이터 전용 주소), 그 외(웹 등)는
/// localhost. 배포 후에는 이 기본값을 서버 도메인/IP로 바꾼다(Phase 0 문서 참고).
const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

String resolveBaseUrl({required bool isAndroid}) {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  return isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
}

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
