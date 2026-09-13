package com.travelfootsteps.exchangerate;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ExchangeRateBatchSchedulerTest {

    @Mock KoreaEximClient client;
    @Mock ExchangeRateRepository repository;

    @Test
    void 콤마_포함_숫자와_100단위_통화를_정규화해서_저장한다() {
        when(client.fetchTodayRates()).thenReturn(List.of(
                new KoreaEximApiItem(1, "USD", "1,320.50"),
                new KoreaEximApiItem(1, "JPY(100)", "895.30")
        ));
        when(repository.findByCurrencyCode(any())).thenReturn(Optional.empty());

        new ExchangeRateBatchScheduler(client, repository).runDaily();

        verify(repository).save(argThat(r -> r.getCurrencyCode().equals("USD")
                && r.getKrwRate().compareTo(new BigDecimal("1320.50")) == 0));
        verify(repository).save(argThat(r -> r.getCurrencyCode().equals("JPY")
                && r.getKrwRate().compareTo(new BigDecimal("8.9530")) == 0));
    }

    @Test
    void result가_1이_아닌_항목은_건너뛴다() {
        when(client.fetchTodayRates()).thenReturn(List.of(new KoreaEximApiItem(2, "USD", "1,320.50")));

        new ExchangeRateBatchScheduler(client, repository).runDaily();

        verify(repository, never()).save(any());
    }

    @Test
    void 이미_캐시된_통화는_새로_저장하지_않고_기존_행을_갱신한다() {
        ExchangeRate existing = ExchangeRate.of("USD", new BigDecimal("1300.0000"),
                java.time.LocalDate.of(2026, 9, 1));
        when(client.fetchTodayRates()).thenReturn(List.of(new KoreaEximApiItem(1, "USD", "1,320.50")));
        when(repository.findByCurrencyCode("USD")).thenReturn(Optional.of(existing));

        new ExchangeRateBatchScheduler(client, repository).runDaily();

        verify(repository, never()).save(any());
        org.assertj.core.api.Assertions.assertThat(existing.getKrwRate())
                .isEqualByComparingTo(new BigDecimal("1320.50"));
    }

    @Test
    void API_호출이_실패해도_예외를_던지지_않는다() {
        when(client.fetchTodayRates())
                .thenThrow(new com.travelfootsteps.externaldata.ExternalApiException("장애"));

        new ExchangeRateBatchScheduler(client, repository).runDaily(); // 예외 없이 반환
    }
}
