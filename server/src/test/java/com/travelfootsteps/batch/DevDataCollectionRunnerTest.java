package com.travelfootsteps.batch;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.context.annotation.Profile;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class DevDataCollectionRunnerTest {

    @Mock DailyDataCollectionScheduler scheduler;

    @Test
    void 기동하면_수집을_한_번_돌린다() {
        new DevDataCollectionRunner(scheduler).run(new DefaultApplicationArguments());

        verify(scheduler, times(1)).runDaily();
    }

    @Test
    void dev_프로필에서만_등록된다() {
        Profile profile = DevDataCollectionRunner.class.getAnnotation(Profile.class);

        assertThat(profile).isNotNull();
        assertThat(profile.value()).containsExactly("dev");
    }
}
