import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 준비물 항목 하나 (서버 ChecklistTemplateResponse에 대응).
/// priority는 "필수/권장" 같은 라벨이 아니라, 화면에 보여줄 순서(오름차순)다.
class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.category,
    required this.title,
    this.description,
    required this.priority,
  });

  final int id;
  final String category; // 서버 원본 값: POWER, PAYMENT, SIM, CLOTHING, DOCUMENT, MONEY 등
  final String title;
  final String? description;
  final int priority; // 낮을수록 먼저 보여줌 (정렬 순서)

  /// 화면 섹션 제목으로 쓸 한글 라벨. 서버에 새 카테고리가 추가되면 여기도 추가해야 한다.
  String get categoryLabelKo {
    switch (category) {
      case 'DOCUMENT':
        return '서류';
      case 'PAYMENT':
        return '결제';
      case 'POWER':
        return '전자기기';
      case 'SIM':
        return '통신';
      case 'CLOTHING':
        return '의류';
      case 'MONEY':
        return '환전';
      default:
        return category; // 모르는 코드는 그대로 보여준다 (조용히 숨기지 않기 위해).
    }
  }

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as int,
        category: json['category'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        priority: json['priority'] as int,
      );
}

/// 서버 준비물 조회(`GET /api/countries/{iso2}/checklist`)를 소비한다.
/// 서버가 공통 항목(country_id = NULL)과 국가별 항목을 우선순위(priority) 오름차순으로
/// 이미 합쳐서 내려준다 (CountryController.checklist 참고).
class ChecklistApi {
  ChecklistApi(this._dio);

  final Dio _dio;

  Future<List<ChecklistItem>> fetchChecklist(String isoAlpha2) async {
    final response = await _dio
        .get<List<dynamic>>('/api/countries/$isoAlpha2/checklist');
    return response.data!
        .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final checklistApiProvider = Provider<ChecklistApi>((ref) {
  return ChecklistApi(ref.watch(apiClientProvider));
});

/// iso2 코드 하나를 받아서 그 나라의 준비물 목록을 가져오는 provider.
final checklistProvider =
    FutureProvider.family<List<ChecklistItem>, String>((ref, isoAlpha2) async {
  final api = ref.watch(checklistApiProvider);
  return api.fetchChecklist(isoAlpha2);
});
