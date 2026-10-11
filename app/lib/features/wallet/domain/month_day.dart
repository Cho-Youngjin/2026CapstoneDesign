/// 지갑 화면의 날짜 표기: 2026-10-09 → "10월 9일". 여행 기간 안의 기록이라 연도는 생략한다.
String formatMonthDay(DateTime date) => '${date.month}월 ${date.day}일';
