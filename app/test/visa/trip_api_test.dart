import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_client_adapter.dart';

// server/.../trip/TripResponse.java 모양.
const _tripJson = '''
{
  "id": 7,
  "countryIso2": "VN",
  "countryNameKo": "베트남",
  "departDate": "2026-12-20",
  "returnDate": "2027-01-09",
  "passportExpiry": "2027-03-15",
  "visaResult": {
    "verdict": "VISA_FREE_EXCEEDED",
    "stayDays": 20,
    "visaFreeDays": 15,
    "passportOk": true,
    "passportValidityMonths": 6,
    "passportShortfallDays": null
  },
  "tasks": [],
  "judgementStale": false
}
''';

TripApi _apiReturning(StubHttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  return TripApi(dio);
}

void main() {
  test('createTrip이 날짜를 yyyy-MM-dd로 POST하고 Trip을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips',
      statusCode: 200,
      body: _tripJson,
    );
    final api = _apiReturning(adapter);

    final trip = await api.createTrip(
      countryIso2: 'VN',
      departDate: DateTime(2026, 12, 20),
      returnDate: DateTime(2027, 1, 9),
      passportExpiry: DateTime(2027, 3, 15),
    );

    expect(trip.id, 7);
    expect(trip.visaResult.verdict, VisaVerdict.visaFreeExceeded);

    final request = adapter.lastRequest!;
    expect(request.method, 'POST');
    expect(request.path, '/api/trips');
    final sent = request.data as Map<String, dynamic>;
    expect(sent, {
      'countryIso2': 'VN',
      'departDate': '2026-12-20',
      'returnDate': '2027-01-09',
      'passportExpiry': '2027-03-15',
    });
  });

  test('getTrip이 /api/trips/{id}로 GET 요청을 보낸다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/7',
      statusCode: 200,
      body: _tripJson,
    );

    final trip = await _apiReturning(adapter).getTrip(7);

    expect(trip.id, 7);
    expect(adapter.lastRequest!.method, 'GET');
    expect(adapter.lastRequest!.path, '/api/trips/7');
  });

  test('refreshTrip이 /api/trips/{id}/refresh로 POST하고 새 판정을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/7/refresh',
      statusCode: 200,
      body: _tripJson,
    );

    final trip = await _apiReturning(adapter).refreshTrip(7);

    expect(trip.id, 7);
    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.path, '/api/trips/7/refresh');
  });

  test('markTaskDone이 완료 처리된 TripTask를 돌려준다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/7/tasks/101/done',
      statusCode: 200,
      body: '{"id":101,"title":"여권 재발급 신청","dueDate":"2026-09-21","done":true}',
    );

    final task = await _apiReturning(adapter).markTaskDone(7, 101);

    expect(task.id, 101);
    expect(task.done, isTrue);
    expect(adapter.lastRequest!.method, 'POST');
  });

  test('서버가 4xx를 돌려주면 DioException을 던진다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips',
      statusCode: 400,
      body: '{"message":"returnDate는 departDate보다 앞설 수 없습니다"}',
    );

    expect(
      () => _apiReturning(adapter).createTrip(
        countryIso2: 'VN',
        departDate: DateTime(2027, 1, 9),
        returnDate: DateTime(2026, 12, 20),
        passportExpiry: DateTime(2027, 3, 15),
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('listTrips가 GET /api/trips 목록을 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips',
      statusCode: 200,
      body: '[{"id":3,"countryIso2":"JP","countryNameKo":"일본",'
          '"departDate":"2026-11-03","returnDate":"2026-11-08","verdict":"VISA_REQUIRED"}]',
    );

    final trips = await _apiReturning(adapter).listTrips();

    expect(adapter.lastRequest!.method, 'GET');
    expect(trips.single.id, 3);
    expect(trips.single.verdict, VisaVerdict.visaRequired);
  });

  test('deleteTrip이 DELETE /api/trips/{id}를 보낸다', () async {
    final adapter = StubHttpClientAdapter(path: '/api/trips/3', statusCode: 204, body: '');

    await _apiReturning(adapter).deleteTrip(3);

    expect(adapter.lastRequest!.method, 'DELETE');
    expect(adapter.lastRequest!.path, '/api/trips/3');
  });

  test('getChecklist가 여행 체크리스트를 체크 여부와 함께 파싱한다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/3/checklist',
      statusCode: 200,
      body: '[{"id":11,"category":"DOCUMENT","title":"여권","description":null,'
          '"priority":1,"checked":true}]',
    );

    final items = await _apiReturning(adapter).getChecklist(3);

    expect(items.single.id, 11);
    expect(items.single.categoryLabelKo, '서류');
    expect(items.single.checked, isTrue);
  });

  test('checkItem이 checked 값을 POST하고 바뀐 항목을 돌려준다', () async {
    final adapter = StubHttpClientAdapter(
      path: '/api/trips/3/checklist/11/check',
      statusCode: 200,
      body: '{"id":11,"category":"DOCUMENT","title":"여권","description":null,'
          '"priority":1,"checked":false}',
    );

    final item = await _apiReturning(adapter).checkItem(3, 11, checked: false);

    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.data, {'checked': false});
    expect(item.checked, isFalse);
  });
}
