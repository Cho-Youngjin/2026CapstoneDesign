package com.travelfootsteps.exchangerate;

// 환율 값이 어느 외부 소스에서 왔는지를 나타낸다.
// - EXIM: 한국수출입은행 고시환율(매매기준율). 영업일 11시 전후에 하루 한 번 갱신된다.
// - ER_API: open.er-api.com 참고환율. 수출입은행이 고시하지 않는 통화(VND, TWD, PHP, TRY, CZK, CNY)만
//   이 값으로 채운다. 은행 고시환율이 아니므로 앱은 "참고환율"과 출처 문구를 함께 보여준다.
// 앱이 출처 표기를 고를 수 있게 응답(ExchangeRateResponse.source)에도 이 이름이 그대로 실린다.
public enum RateSource {
    EXIM,
    ER_API
}
