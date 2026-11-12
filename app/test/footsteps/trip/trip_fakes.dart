import 'package:app/features/footsteps/trip/trip_period.dart';

/// 테스트용 여행 기간. 날짜는 시각 없는 달력 날짜로 준다.
TripPeriod period(int id, DateTime depart, DateTime ret, {String iso2 = 'KR', String nameKo = '대한민국'}) =>
    TripPeriod(tripId: id, countryIso2: iso2, countryNameKo: nameKo, departDate: depart, returnDate: ret);
