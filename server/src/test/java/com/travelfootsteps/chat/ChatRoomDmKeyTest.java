package com.travelfootsteps.chat;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** DM 열쇠({@link ChatRoom#dmKeyOf}) 단위 테스트. */
class ChatRoomDmKeyTest {

    @Test
    void 누가_먼저_열든_같은_열쇠가_나온다() {
        assertThat(ChatRoom.dmKeyOf("uid-a", "uid-b")).isEqualTo(ChatRoom.dmKeyOf("uid-b", "uid-a"));
    }

    @Test
    void uid에_구분자가_들어가도_서로_다른_두_쌍은_열쇠가_겹치지_않는다() {
        // 그냥 "|"로 이으면 둘 다 "a|b|c"가 된다.
        assertThat(ChatRoom.dmKeyOf("a", "b|c")).isNotEqualTo(ChatRoom.dmKeyOf("a|b", "c"));
        assertThat(ChatRoom.dmKeyOf("1:a", "b")).isNotEqualTo(ChatRoom.dmKeyOf("1", "a|b"));
    }

    @Test
    void 가장_긴_uid_두_개도_컬럼_길이_안에_들어간다() {
        String longest = "x".repeat(128);
        String other = "y".repeat(128);

        assertThat(ChatRoom.dmKeyOf(longest, other).length()).isLessThanOrEqualTo(270);
    }
}
