import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/checklist_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final List<dynamic> body;
  RequestOptions? capturedRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options,
      Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture,
      ) async {
    capturedRequest = options;
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
  group('ChecklistItem.fromJson', () {
    test('서버 응답 필드를 그대로 파싱한다 (priority는 숫자)', () {
      final item = ChecklistItem.fromJson({
        'id': 1,
        'category': '결제',
        'title': '소액권 현지통화 사전 환전',
        'description': '노점·시장 대비.',
        'priority': 2,
      });

      expect(item.id, 1);
      expect(item.category, '결제');
      expect(item.title, '소액권 현지통화 사전 환전');
      expect(item.priority, 2);
    });

    test('설명이 없어도 파싱된다', () {
      final item = ChecklistItem.fromJson({
        'id': 2,
        'category': '건강',
        'title': '상비약',
        'priority': 5,
      });

      expect(item.description, isNull);
    });
  });

  group('ChecklistApi.fetchChecklist', () {
    test('GET /api/countries/{iso2}/checklist로 요청하고 목록을 파싱한다', () async {
      final adapter = _StubAdapter(200, [
        {'id': 1, 'category': '서류', 'title': '여권 원본 + 사본', 'priority': 1},
        {'id': 2, 'category': '결제', 'title': '소액권 현지통화', 'priority': 2},
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = ChecklistApi(dio);

      final items = await api.fetchChecklist('VN');

      expect(adapter.capturedRequest!.path, '/api/countries/VN/checklist');
      expect(adapter.capturedRequest!.method, 'GET');
      expect(items.length, 2);
      expect(items[0].title, '여권 원본 + 사본');
      expect(items[1].priority, 2);
    });

    test('서버 오류(500)면 예외를 던진다', () async {
      final adapter = _StubAdapter(500, []);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = adapter;
      final api = ChecklistApi(dio);

      expect(() => api.fetchChecklist('VN'), throwsA(isA<DioException>()));
    });
  });
}