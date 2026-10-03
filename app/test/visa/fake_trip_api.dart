import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:dio/dio.dart';

/// 테스트용 샘플 여행. 필요한 값만 바꿔 쓴다.
Trip sampleTrip({int id = 7, String iso2 = 'VN', String nameKo = '베트남'}) {
  return Trip(
    id: id,
    countryIso2: iso2,
    countryNameKo: nameKo,
    departDate: DateTime(2026, 12, 20),
    returnDate: DateTime(2027, 1, 9),
    passportExpiry: DateTime(2027, 3, 15),
    visaResult: const VisaResult(
      verdict: VisaVerdict.visaFreeOk,
      stayDays: 20,
      visaFreeDays: 45,
      passportOk: true,
      passportValidityMonths: 6,
    ),
    tasks: const [],
  );
}

/// 서버 없이 TripApi를 쓰는 화면·provider를 테스트하기 위한 가짜 구현.
/// 호출 인자를 기록하고, 상태 코드를 지정하면 그 코드의 DioException을 던진다.
class FakeTripApi implements TripApi {
  FakeTripApi({
    Trip? tripToReturn,
    this.createTripStatusCode,
    this.getTripStatusCode,
  }) : tripToReturn = tripToReturn ?? sampleTrip();

  final Trip tripToReturn;
  final int? createTripStatusCode;
  final int? getTripStatusCode;

  final List<Map<String, Object>> createTripCalls = [];
  final List<int> getTripCalls = [];

  @override
  Future<Trip> createTrip({
    required String countryIso2,
    required DateTime departDate,
    required DateTime returnDate,
    required DateTime passportExpiry,
  }) async {
    createTripCalls.add({
      'countryIso2': countryIso2,
      'departDate': departDate,
      'returnDate': returnDate,
      'passportExpiry': passportExpiry,
    });
    if (createTripStatusCode != null) {
      throw _error('/api/trips', createTripStatusCode!);
    }
    return tripToReturn;
  }

  @override
  Future<Trip> getTrip(int id) async {
    getTripCalls.add(id);
    if (getTripStatusCode != null) {
      throw _error('/api/trips/$id', getTripStatusCode!);
    }
    return tripToReturn;
  }

  @override
  Future<Trip> refreshTrip(int id) async => tripToReturn;

  @override
  Future<TripTask> markTaskDone(int tripId, int taskId) async =>
      tripToReturn.tasks.firstWhere((t) => t.id == taskId).copyWith(done: true);

  DioException _error(String path, int statusCode) {
    final options = RequestOptions(path: path);
    return DioException.badResponse(
      statusCode: statusCode,
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: statusCode),
    );
  }
}
