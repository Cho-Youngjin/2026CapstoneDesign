package com.travelfootsteps.batch;

import com.travelfootsteps.alert.TravelAlertCollector;
import com.travelfootsteps.country.Country;
import com.travelfootsteps.country.CountryRepository;
import com.travelfootsteps.embassy.EmbassyCollector;
import com.travelfootsteps.visa.VisaRequirementCollector;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DailyDataCollectionSchedulerTest {

    @Mock CountryRepository countryRepository;
    @Mock VisaRequirementCollector visaCollector;
    @Mock TravelAlertCollector alertCollector;
    @Mock EmbassyCollector embassyCollector;

    @InjectMocks
    DailyDataCollectionScheduler scheduler;

    @Test
    void 모든_국가에_대해_세_수집기를_전부_호출한다() {
        Country vn = mockCountry("VN");
        Country jp = mockCountry("JP");
        when(countryRepository.findAll()).thenReturn(List.of(vn, jp));

        scheduler.runDaily();

        verify(visaCollector, times(1)).collectOne(vn);
        verify(visaCollector, times(1)).collectOne(jp);
        verify(alertCollector, times(1)).collectOne(vn);
        verify(embassyCollector, times(1)).collectOne(vn);
    }

    @Test
    void 한_국가에서_예외가_나도_나머지_국가는_계속_처리한다() {
        Country vn = mockCountry("VN");
        Country jp = mockCountry("JP");
        when(countryRepository.findAll()).thenReturn(List.of(vn, jp));
        org.mockito.Mockito.doThrow(new RuntimeException("예상치 못한 오류"))
                .when(visaCollector).collectOne(vn);

        scheduler.runDaily();

        verify(visaCollector, times(1)).collectOne(jp);
        verify(alertCollector, times(1)).collectOne(jp);
    }

    private Country mockCountry(String iso2) {
        Country country = org.mockito.Mockito.mock(Country.class);
        // getIsoAlpha2()는 실패 시 로그 메시지(collectSafely의 catch 블록)에서만 쓰인다 —
        // 정상 처리되는 국가에서는 전혀 호출되지 않으므로, Mockito의 기본 strict-stubs 검사가
        // "쓰이지 않은 스터빙"으로 오탐(UnnecessaryStubbingException)하지 않도록 lenient로 표시한다.
        org.mockito.Mockito.lenient().when(country.getIsoAlpha2()).thenReturn(iso2);
        return country;
    }
}
