package com.travelfootsteps.chat;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ChatRoomPreviewTest {

    @Test
    void 짧은_메시지는_그대로_미리보기가_된다() {
        assertThat(ChatRoom.previewOf(ChatMessage.text(1L, "uid-a", "안녕"))).isEqualTo("안녕");
    }

    @Test
    void 긴_메시지는_100자로_자른다() {
        String text = "가".repeat(150);

        assertThat(ChatRoom.previewOf(ChatMessage.text(1L, "uid-a", text))).isEqualTo("가".repeat(100));
    }

    @Test
    void 자르는_자리가_이모지_한가운데면_이모지_앞에서_자른다() {
        // 😀는 UTF-16 두 칸(서로게이트 쌍)이다. 99자 + 😀이면 100번째 칸이 이모지의 앞 절반이 된다.
        String text = "a".repeat(99) + "😀" + "뒤";

        String preview = ChatRoom.previewOf(ChatMessage.text(1L, "uid-a", text));

        assertThat(preview).isEqualTo("a".repeat(99));
        assertThat(Character.isHighSurrogate(preview.charAt(preview.length() - 1))).isFalse();
    }

    @Test
    void 이모지가_100자_안에_온전히_들어가면_남긴다() {
        String text = "a".repeat(98) + "😀" + "뒤";

        assertThat(ChatRoom.previewOf(ChatMessage.text(1L, "uid-a", text))).isEqualTo("a".repeat(98) + "😀");
    }
}
