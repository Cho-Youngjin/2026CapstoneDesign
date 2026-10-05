/// 여행 계획과 비자 판정 결과 모델.
///
/// JSON 모양은 서버의 `trip/TripResponse.java`, `VisaResultResponse.java`,
/// `TripTaskResponse.java`와 필드명까지 정확히 맞춘다. 서버 DTO가 바뀌면
/// 이 파일의 `fromJson`만 고치면 된다.
library;

/// 서버 `visa/VisaVerdict.java`의 wireValue와 문자 그대로 일치해야 한다.
enum VisaVerdict {
  visaFreeOk('VISA_FREE_OK'),
  visaFreeExceeded('VISA_FREE_EXCEEDED'),
  visaRequired('VISA_REQUIRED'),
  unverified('UNVERIFIED');

  const VisaVerdict(this.wireValue);

  final String wireValue;

  /// 모르는 값이 오면 앱이 죽지 않도록 "영사관 확인 필요"(unverified)로 degrade한다.
  static VisaVerdict fromWire(String value) => VisaVerdict.values.firstWhere(
        (v) => v.wireValue == value,
        orElse: () => VisaVerdict.unverified,
      );
}

class VisaResult {
  const VisaResult({
    required this.verdict,
    required this.stayDays,
    this.visaFreeDays,
    required this.passportOk,
    this.passportValidityMonths,
    this.passportShortfallDays,
  });

  final VisaVerdict verdict;
  final int stayDays;

  /// Tier B 미검증 국가는 null일 수 있다 — "영사관 확인 필요"로 표시한다.
  final int? visaFreeDays;

  final bool passportOk;
  final int? passportValidityMonths;
  final int? passportShortfallDays;

  factory VisaResult.fromJson(Map<String, dynamic> json) => VisaResult(
        verdict: VisaVerdict.fromWire(json['verdict'] as String),
        stayDays: json['stayDays'] as int,
        visaFreeDays: json['visaFreeDays'] as int?,
        passportOk: json['passportOk'] as bool,
        passportValidityMonths: json['passportValidityMonths'] as int?,
        passportShortfallDays: json['passportShortfallDays'] as int?,
      );
}

class TripTask {
  const TripTask({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.done,
  });

  final int id;
  final String title;

  /// 날짜만 의미가 있다 (서버는 `yyyy-MM-dd`로 보낸다).
  final DateTime dueDate;
  final bool done;

  /// 마감일이 [now]의 날짜보다 앞서는데 아직 완료되지 않았다 —
  /// 스펙 §6-①: "이미 지난 날짜는 지금 바로"로 표시한다.
  ///
  /// 날짜 단위로 비교한다. 마감일이 오늘인 항목은 아직 지난 것으로 보지 않는다.
  bool isPastDueAt(DateTime now) {
    if (done) return false;
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.isBefore(today);
  }

  bool get isPastDue => isPastDueAt(DateTime.now());

  factory TripTask.fromJson(Map<String, dynamic> json) => TripTask(
        id: json['id'] as int,
        title: json['title'] as String,
        dueDate: DateTime.parse(json['dueDate'] as String),
        done: json['done'] as bool,
      );

  TripTask copyWith({bool? done}) => TripTask(
        id: id,
        title: title,
        dueDate: dueDate,
        done: done ?? this.done,
      );
}

class Trip {
  const Trip({
    required this.id,
    required this.countryIso2,
    required this.countryNameKo,
    required this.departDate,
    required this.returnDate,
    required this.passportExpiry,
    required this.visaResult,
    required this.tasks,
    this.judgementStale = false,
  });

  final int id;
  final String countryIso2;
  final String countryNameKo;
  final DateTime departDate;
  final DateTime returnDate;
  final DateTime passportExpiry;
  final VisaResult visaResult;
  final List<TripTask> tasks;

  /// 여행 생성 이후 비자 판정 기준 데이터가 바뀌었다 (2026-09-12 리뷰 반영).
  /// true면 화면에서 새로고침 여부를 묻고, 동의 시 `POST /api/trips/{id}/refresh`를 호출한다.
  final bool judgementStale;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as int,
        countryIso2: json['countryIso2'] as String,
        countryNameKo: json['countryNameKo'] as String,
        departDate: DateTime.parse(json['departDate'] as String),
        returnDate: DateTime.parse(json['returnDate'] as String),
        passportExpiry: DateTime.parse(json['passportExpiry'] as String),
        visaResult:
            VisaResult.fromJson(json['visaResult'] as Map<String, dynamic>),
        tasks: (json['tasks'] as List)
            .map((e) => TripTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        judgementStale: json['judgementStale'] as bool? ?? false,
      );

  /// id가 같은 일정 항목 하나만 교체한 새 Trip을 돌려준다 (원본 불변).
  Trip replaceTask(TripTask updated) => Trip(
        id: id,
        countryIso2: countryIso2,
        countryNameKo: countryNameKo,
        departDate: departDate,
        returnDate: returnDate,
        passportExpiry: passportExpiry,
        visaResult: visaResult,
        tasks: [for (final t in tasks) if (t.id == updated.id) updated else t],
        judgementStale: judgementStale,
      );
}
