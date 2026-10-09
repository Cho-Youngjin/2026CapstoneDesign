package com.travelfootsteps.exchangerate;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

class ExchangeRateTest {

    static final LocalDate D6 = LocalDate.of(2026, 10, 6);
    static final LocalDate D7 = LocalDate.of(2026, 10, 7);
    static final LocalDate D8 = LocalDate.of(2026, 10, 8);

    @Test
    void 더_늦은_고시일이_오면_기존값을_이전값으로_밀어낸다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);

        rate.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);

        assertThat(rate.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(rate.getBaseDate()).isEqualTo(D8);
        assertThat(rate.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(rate.getPreviousBaseDate()).isEqualTo(D7);
    }

    @Test
    void 같은_고시일이면_현재값만_바꾸고_이전값은_유지한다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);

        rate.apply(new BigDecimal("1340.0"), D8, RateSource.EXIM);

        assertThat(rate.getKrwRate()).isEqualByComparingTo("1340.0");
        assertThat(rate.getBaseDate()).isEqualTo(D8);
        assertThat(rate.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(rate.getPreviousBaseDate()).isEqualTo(D7);
    }

    @Test
    void 더_이른_고시일은_이전값이_비어_있을_때만_채운다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D8, RateSource.EXIM);

        rate.apply(new BigDecimal("1333.6"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1300.0"), D6, RateSource.EXIM);

        assertThat(rate.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(rate.getBaseDate()).isEqualTo(D8);
        assertThat(rate.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(rate.getPreviousBaseDate()).isEqualTo(D7);
    }

    @Test
    void 등락률은_소수_둘째자리까지_반올림한다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);

        assertThat(rate.changePercent()).isEqualByComparingTo("0.42");
    }

    @Test
    void 하락하면_등락률이_음수다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D7, RateSource.EXIM);
        rate.apply(new BigDecimal("1333.6"), D8, RateSource.EXIM);

        assertThat(rate.changePercent()).isEqualByComparingTo("-0.42");
    }

    @Test
    void 이전값이_없으면_등락률은_null이다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D8, RateSource.EXIM);

        assertThat(rate.changePercent()).isNull();
    }

    @Test
    void 출처를_생략하면_수출입은행으로_본다() {
        ExchangeRate rate = ExchangeRate.of("USD", new BigDecimal("1339.2"), D8);

        assertThat(rate.getSource()).isEqualTo(RateSource.EXIM);
    }
}
