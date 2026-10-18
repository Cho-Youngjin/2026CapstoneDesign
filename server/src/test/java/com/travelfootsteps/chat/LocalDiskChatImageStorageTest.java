package com.travelfootsteps.chat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 디스크 저장소 단위 테스트 — 파일 이름과 경로 조작 방어만 본다. */
class LocalDiskChatImageStorageTest {

    @TempDir Path dir;

    @Test
    void 서버가_만든_이름으로_저장하고_그대로_읽고_지운다() throws Exception {
        LocalDiskChatImageStorage storage = new LocalDiskChatImageStorage(dir.toString());

        String path = storage.save(new byte[]{1, 2, 3}, ChatImageFormat.PNG);

        assertThat(path).matches("[0-9a-f-]{36}\\.png");
        assertThat(storage.load(path)).containsExactly(1, 2, 3);
        storage.delete(path);
        assertThat(Files.list(dir)).isEmpty();
    }

    @Test
    void 저장_디렉터리_밖을_가리키는_경로는_거부한다() throws Exception {
        LocalDiskChatImageStorage storage = new LocalDiskChatImageStorage(dir.resolve("images").toString());
        Files.writeString(dir.resolve("secret.txt"), "비밀");

        assertThatThrownBy(() -> storage.load("../secret.txt")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> storage.delete("../secret.txt")).isInstanceOf(IllegalArgumentException.class);
        assertThat(dir.resolve("secret.txt")).exists();
    }

    @Test
    void 저장_디렉터리가_없으면_만든다() {
        LocalDiskChatImageStorage storage = new LocalDiskChatImageStorage(dir.resolve("a/b").toString());

        String path = storage.save(new byte[]{9}, ChatImageFormat.JPEG);

        assertThat(dir.resolve("a/b").resolve(path)).exists();
    }

    @Test
    void 매직_넘버로_형식을_판정한다() {
        assertThat(ChatImageFormat.detect(new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0})).contains(ChatImageFormat.JPEG);
        assertThat(ChatImageFormat.detect(new byte[]{(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}))
                .contains(ChatImageFormat.PNG);
        assertThat(ChatImageFormat.detect("RIFF\0\0\0\0WEBP".getBytes())).contains(ChatImageFormat.WEBP);
        assertThat(ChatImageFormat.detect("RIFF\0\0\0\0WAVE".getBytes())).isEmpty();   // RIFF지만 WEBP가 아님
        assertThat(ChatImageFormat.detect(new byte[]{(byte) 0xFF})).isEmpty();          // 너무 짧음
        assertThat(ChatImageFormat.detect("GIF89a".getBytes())).isEmpty();
    }
}
