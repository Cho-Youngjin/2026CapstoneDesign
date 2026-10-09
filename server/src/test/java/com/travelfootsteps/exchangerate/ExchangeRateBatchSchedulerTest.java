package com.travelfootsteps.exchangerate;

import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.externaldata.ExternalApiException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
// 저장소 스텁을 setUp에서 한꺼번에 깔아 두는데, 모든 테스트가 그 스텁을 다 쓰지는 않는다.
@MockitoSettings(strictness = Strictness.LENIENT)
class ExchangeRateBatchSchedulerTest {

    static final LocalDate D6 = LocalDate.of(2026, 10, 6);
    static final LocalDate D7 = LocalDate.of(2026, 10, 7);
    static final LocalDate D8 = LocalDate.of(2026, 10, 8);
    static final LocalDate D9 = LocalDate.of(2026, 10, 9); // 한글날(공휴일)
    // 2026-10-09 00:02:31 UTC = 2026-10-09 09:02:31 KST
    static final long ER_UPDATED_UNIX = 1791504151L;
    // 2026-10-08 15:30:00 UTC = 2026-10-09 00:30:00 KST (UTC 날짜와 KST 날짜가 다른 시각)
    static final long ER_UPDATED_UNIX_UTC_PREV_DAY = 1791473400L;

    @Mock KoreaEximClient eximClient;
    @Mock OpenErApiClient erApiClient;
    @Mock ExchangeRateRepository repository;
    @Mock CountryRepository countryRepository;

    // 저장소 목을 메모리 맵처럼 동작시킨다 — save한 엔티티를 findByCurrencyCode로 다시 꺼낼 수 있어야
    // apply()가 이전값을 쌓는 과정을 검증할 수 있다.
    final Map<String, ExchangeRate> stored = new HashMap<>();
    ExchangeRateBatchScheduler scheduler;

    @BeforeEach
    void setUp() {
        when(repository.findByCurrencyCode(anyString()))
                .thenAnswer(inv -> Optional.ofNullable(stored.get(inv.getArgument(0, String.class))));
        when(repository.save(any(ExchangeRate.class))).thenAnswer(inv -> {
            ExchangeRate rate = inv.getArgument(0);
            stored.put(rate.getCurrencyCode(), rate);
            return rate;
        });
        when(repository.findAll()).thenAnswer(inv -> new ArrayList<>(stored.values()));
        when(repository.count()).thenAnswer(inv -> (long) stored.size());
        when(repository.existsBySourceAndPreviousKrwRateIsNull(any())).thenAnswer(inv ->
                stored.values().stream().anyMatch(r ->
                        r.getSource() == inv.getArgument(0) && r.getPreviousKrwRate() == null));
        when(repository.existsBySource(any())).thenAnswer(inv ->
                stored.values().stream().anyMatch(r -> r.getSource() == inv.getArgument(0)));
        countries("USD", "JPY", "VND");
        scheduler = new ExchangeRateBatchScheduler(eximClient, erApiClient, repository, countryRepository);
    }

    void countries(String... currencyCodes) {
        List<Country> list = Arrays.stream(currencyCodes).map(code -> {
            Country country = mock(Country.class);
            when(country.getCurrencyCode()).thenReturn(code);
            return country;
        }).toList();
        when(countryRepository.findAll()).thenReturn(list);
    }

    static OpenErApiResponse erRates(long updatedUnix, String... codeAndRate) {
        Map<String, BigDecimal> rates = new LinkedHashMap<>();
        for (int i = 0; i < codeAndRate.length; i += 2) {
            rates.put(codeAndRate[i], new BigDecimal(codeAndRate[i + 1]));
        }
        return new OpenErApiResponse("success", updatedUnix, rates);
    }

    @Test
    void 수출입은행_값을_1단위_원화로_정규화해_저장하고_KRW는_저장하지_않는다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(
                new KoreaEximApiItem(1, "USD", "1,339.2"),
                new KoreaEximApiItem(1, "JPY(100)", "847.46"),
                new KoreaEximApiItem(1, "KRW", "1")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(stored.get("USD").getBaseDate()).isEqualTo(D8);
        assertThat(stored.get("USD").getSource()).isEqualTo(RateSource.EXIM);
        assertThat(stored.get("JPY").getKrwRate()).isEqualByComparingTo("8.4746");
        assertThat(stored).doesNotContainKey("KRW");
    }

    @Test
    void result가_1이_아닌_항목은_건너뛴다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(4, null, null)));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored).doesNotContainKeys("USD", "JPY");
    }

    @Test
    void 수출입은행에_없는_통화만_참고환율로_채운다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(erApiClient.fetchKrwBase())
                .thenReturn(erRates(ER_UPDATED_UNIX, "USD", "0.000745", "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored.get("USD").getSource()).isEqualTo(RateSource.EXIM);
        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
        assertThat(stored.get("VND").getKrwRate()).isEqualByComparingTo("0.051934");
        assertThat(stored.get("VND").getBaseDate()).isEqualTo(D9);
    }

    @Test
    void 공휴일에_수출입은행이_빈_배열이면_기존_수출입은행_통화를_참고환율로_덮지_않는다() {
        stored.put("USD", ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM));
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(erApiClient.fetchKrwBase())
                .thenReturn(erRates(ER_UPDATED_UNIX, "USD", "0.000745", "VND", "19.255146"));

        scheduler.refresh(D9);

        assertThat(stored.get("USD").getSource()).isEqualTo(RateSource.EXIM);
        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(stored.get("USD").getBaseDate()).isEqualTo(D7);
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
    }

    @Test
    void 참고환율_고시일은_UTC가_아니라_KST_날짜다() {
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(erApiClient.fetchKrwBase())
                .thenReturn(erRates(ER_UPDATED_UNIX_UTC_PREV_DAY, "VND", "19.255146"));

        scheduler.refresh(D9);

        assertThat(stored.get("VND").getBaseDate()).isEqualTo(D9);
    }

    @Test
    void 수출입은행_호출이_실패해도_참고환율은_갱신한다() {
        when(eximClient.fetchRates(D8)).thenThrow(new ExternalApiException("장애"));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.refresh(D8);

        assertThat(stored.get("VND").getKrwRate()).isEqualByComparingTo("0.051934");
    }

    @Test
    void 참고환율_호출이_실패해도_수출입은행_값은_저장되고_예외를_던지지_않는다() {
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(erApiClient.fetchKrwBase()).thenThrow(new ExternalApiException("장애"));

        scheduler.refresh(D8);

        assertThat(stored.get("USD").getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(stored).doesNotContainKey("VND");
    }

    @Test
    void 참고환율_대상이_없으면_open_er_api를_호출하지_않는다() {
        countries("USD");
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));

        scheduler.refresh(D8);

        verify(erApiClient, never()).fetchKrwBase();
    }

    @Test
    void 보정_실행은_최근_영업일_2개를_찾아_이전값까지_채운다() {
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(eximClient.fetchRates(D7)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,333.6")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.backfillIfNeeded(D9);

        ExchangeRate usd = stored.get("USD");
        assertThat(usd.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(usd.getBaseDate()).isEqualTo(D8);
        assertThat(usd.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(usd.getPreviousBaseDate()).isEqualTo(D7);
        assertThat(usd.changePercent()).isEqualByComparingTo("0.42");
        verify(eximClient, never()).fetchRates(D6);
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
    }

    @Test
    void 보정_실행은_최대_10일까지만_거슬러_올라간다() {
        when(eximClient.fetchRates(any())).thenReturn(List.of());

        scheduler.backfillIfNeeded(D9);

        verify(eximClient, times(ExchangeRateBatchScheduler.BACKFILL_MAX_DAYS)).fetchRates(any());
    }

    @Test
    void 보정_실행_중_한_날짜_호출이_실패해도_다음_날짜로_넘어간다() {
        when(eximClient.fetchRates(D9)).thenThrow(new ExternalApiException("장애"));
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(eximClient.fetchRates(D7)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,333.6")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.backfillIfNeeded(D9);

        assertThat(stored.get("USD").getPreviousKrwRate()).isEqualByComparingTo("1333.6");
    }

    @Test
    void 참고환율_행만_있고_수출입은행_행이_없으면_보정_실행으로_수출입은행_값을_되찾는다() {
        // 첫 기동 때 수출입은행 보정이 실패해서 참고환율이 USD까지 채워 둔 상태
        stored.put("USD", ExchangeRate.of("USD", new BigDecimal("1342.281900"), D9, RateSource.ER_API));
        stored.put("VND", ExchangeRate.of("VND", new BigDecimal("0.051934"), D9, RateSource.ER_API));
        when(eximClient.fetchRates(D9)).thenReturn(List.of());
        when(eximClient.fetchRates(D8)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,339.2")));
        when(eximClient.fetchRates(D7)).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,333.6")));
        when(erApiClient.fetchKrwBase()).thenReturn(erRates(ER_UPDATED_UNIX, "VND", "19.255146"));

        scheduler.backfillIfNeeded(D9);

        ExchangeRate usd = stored.get("USD");
        assertThat(usd.getSource()).isEqualTo(RateSource.EXIM);
        assertThat(usd.getKrwRate()).isEqualByComparingTo("1339.2");
        assertThat(usd.getBaseDate()).isEqualTo(D8);
        assertThat(usd.getPreviousKrwRate()).isEqualByComparingTo("1333.6");
        assertThat(usd.getPreviousBaseDate()).isEqualTo(D7);
        assertThat(stored.get("VND").getSource()).isEqualTo(RateSource.ER_API);
    }

    @Test
    void 수출입은행_행이_모두_이전값을_가지면_보정_실행을_건너뛴다() {
        ExchangeRate usd = ExchangeRate.of("USD", new BigDecimal("1333.6"), D7, RateSource.EXIM);
        usd.apply(new BigDecimal("1339.2"), D8, RateSource.EXIM);
        stored.put("USD", usd);

        scheduler.backfillIfNeeded(D9);

        verify(eximClient, never()).fetchRates(any());
    }
}
