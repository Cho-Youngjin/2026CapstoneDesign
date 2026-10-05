import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class TranslationResult {
  const TranslationResult({required this.translatedText, this.detectedSourceLanguage});

  final String translatedText;
  final String? detectedSourceLanguage;

  factory TranslationResult.fromJson(Map<String, dynamic> json) =>
      TranslationResult(
        translatedText: json['translatedText'] as String,
        detectedSourceLanguage: json['detectedSourceLanguage'] as String?,
      );
}

/// 서버 번역 프록시(`POST /api/translate`)를 소비한다.
/// 구글 번역 API 키는 서버에만 있고, 앱은 이 서버만 호출한다.
class TranslateApi {
  TranslateApi(this._dio);

  final Dio _dio;

  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/translate',
      data: {
        'text': text,
        'targetLanguage': targetLanguage,
        'sourceLanguage': ?sourceLanguage,
      },
    );
    return TranslationResult.fromJson(response.data!);
  }
}

final translateApiProvider = Provider<TranslateApi>((ref) {
  return TranslateApi(ref.watch(apiClientProvider));
});