import 'package:app/features/visa/data/trip_api.dart';
import 'package:app/features/visa/models/trip.dart';
import 'package:app/features/visa/models/trip_checklist_item.dart';
import 'package:app/features/visa/models/trip_summary.dart';
import 'package:dio/dio.dart';

/// 테스트용 샘플 여행. 필요한 값만 바꿔 쓴다.
Trip sampleTrip({
  int id = 7,
  String iso2 = 'VN',
  String nameKo = '베트남',
  VisaResult? visaResult,
  List<TripTask> tasks = const [],
  bool judgementStale = false,
}) {
  return Trip(
    id: id,
    countryIso2: iso2,
    countryNameKo: nameKo,
    departDate: DateTime(2026, 12, 20),
    returnDate: DateTime(2027, 1, 9),
    passportExpiry: DateTime(2027, 3, 15),
    visaResult: visaResult ??
        const VisaResult(
          verdict: VisaVerdict.visaFreeOk,
          stayDays: 20,
          visaFreeDays: 45,
          passportOk: true,
          passportValidityMonths: 6,
        ),
    tasks: tasks,
    judgementStale: judgementStale,
  );
}

/// 테스트용 여행 요약. 날짜를 주지 않으면 2026-12-20~2027-01-09.
TripSummary sampleSummary({
  int id = 7,
  String iso2 = 'VN',
  String nameKo = '베트남',
  DateTime? depart,
  DateTime? ret,
  VisaVerdict verdict = VisaVerdict.visaFreeOk,
}) {
  return TripSummary(
    id: id,
    countryIso2: iso2,
    countryNameKo: nameKo,
    departDate: depart ?? DateTime(2026, 12, 20),
    returnDate: ret ?? DateTime(2027, 1, 9),
    verdict: verdict,
  );
}

/// 서버 없이 TripApi를 쓰는 화면·provider를 테스트하기 위한 가짜 구현.
/// 호출 인자를 기록하고, 상태 코드를 지정하면 그 코드의 DioException을 던진다.
class FakeTripApi implements TripApi {
  FakeTripApi({
    Trip? tripToReturn,
    this.tripAfterRefresh,
    this.createTripStatusCode,
    this.getTripStatusCode,
    this.trips = const [],
    this.listTripsStatusCode,
    this.deleteTripStatusCode,
    this.checklist = const [],
    this.getChecklistStatusCode,
    this.checkItemStatusCode,
  }) : tripToReturn = tripToReturn ?? sampleTrip();

  final Trip tripToReturn;

  /// refreshTrip이 돌려줄 여행. 지정하지 않으면 [tripToReturn]을 그대로 준다.
  final Trip? tripAfterRefresh;

  final int? createTripStatusCode;
  final int? getTripStatusCode;
  final List<TripSummary> trips;
  final int? listTripsStatusCode;
  final int? deleteTripStatusCode;
  final List<TripChecklistItem> checklist;
  final int? getChecklistStatusCode;
  final int? checkItemStatusCode;

  final List<Map<String, Object>> createTripCalls = [];
  final List<int> getTripCalls = [];
  final List<int> refreshTripCalls = [];
  final List<({int tripId, int taskId})> markTaskDoneCalls = [];
  int listTripsCalls = 0;
  final List<int> deleteTripCalls = [];
  final List<int> getChecklistCalls = [];
  final List<({int tripId, int itemId, bool checked})> checkItemCalls = [];

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
  Future<Trip> refreshTrip(int id) async {
    refreshTripCalls.add(id);
    return tripAfterRefresh ?? tripToReturn;
  }

  @override
  Future<TripTask> markTaskDone(int tripId, int taskId) async {
    markTaskDoneCalls.add((tripId: tripId, taskId: taskId));
    return tripToReturn.tasks.firstWhere((t) => t.id == taskId).copyWith(done: true);
  }

  @override
  Future<List<TripSummary>> listTrips() async {
    listTripsCalls++;
    if (listTripsStatusCode != null) {
      throw _error('/api/trips', listTripsStatusCode!);
    }
    return trips;
  }

  @override
  Future<void> deleteTrip(int id) async {
    deleteTripCalls.add(id);
    if (deleteTripStatusCode != null) {
      throw _error('/api/trips/$id', deleteTripStatusCode!);
    }
  }

  @override
  Future<List<TripChecklistItem>> getChecklist(int tripId) async {
    getChecklistCalls.add(tripId);
    if (getChecklistStatusCode != null) {
      throw _error('/api/trips/$tripId/checklist', getChecklistStatusCode!);
    }
    return checklist;
  }

  @override
  Future<TripChecklistItem> checkItem(int tripId, int itemId, {required bool checked}) async {
    checkItemCalls.add((tripId: tripId, itemId: itemId, checked: checked));
    if (checkItemStatusCode != null) {
      throw _error('/api/trips/$tripId/checklist/$itemId/check', checkItemStatusCode!);
    }
    final item = checklist.firstWhere((i) => i.id == itemId);
    return TripChecklistItem(
      id: item.id,
      category: item.category,
      title: item.title,
      description: item.description,
      priority: item.priority,
      checked: checked,
    );
  }

  DioException _error(String path, int statusCode) {
    final options = RequestOptions(path: path);
    return DioException.badResponse(
      statusCode: statusCode,
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: statusCode),
    );
  }
}
