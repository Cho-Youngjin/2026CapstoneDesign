package com.travelfootsteps.chat;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;

/**
 * 채팅 사진을 서버 디스크에 저장한다 (Plan D Task 6).
 *
 * <p>{@code @Component}: 스프링이 이 클래스를 빈으로 만들어 {@link ChatImageStorage}가 필요한 곳(MessageService)에
 * 넣어 준다. 구현이 하나뿐이라 따로 고를 필요가 없다.
 *
 * <p>{@code @Value("${chat.image-dir:./data/chat-images}")}: application.yml의 {@code chat.image-dir} 값을 생성자
 * 인자로 받는다. 값이 없으면 콜론 뒤의 기본값(서버를 실행한 폴더 아래 ./data/chat-images)을 쓴다. 배포 때는 VM의
 * 영구 디스크 경로를 환경변수로 넣는다(테스트는 임시 폴더를 넣는다).
 *
 * <p><b>파일 이름은 서버가 만든 UUID만 쓴다.</b> 사용자가 보낸 이름에는 {@code ../} 같은 경로 조작이 섞일 수 있다.
 * 읽기·지우기도 저장 폴더 밖을 가리키는 경로면 거부한다 — DB 값이 어긋나도 다른 파일을 건드리지 않게 하는 이중 잠금이다.
 */
@Component
public class LocalDiskChatImageStorage implements ChatImageStorage {

    private final Path root;

    public LocalDiskChatImageStorage(@Value("${chat.image-dir:./data/chat-images}") String imageDir) {
        this.root = Path.of(imageDir).toAbsolutePath().normalize();
    }

    @Override
    public String save(byte[] bytes, ChatImageFormat format) {
        String name = UUID.randomUUID() + "." + format.extension;
        try {
            Files.createDirectories(root);
            Files.write(resolve(name), bytes);
        } catch (IOException e) {
            throw new UncheckedIOException("채팅 사진을 저장하지 못했습니다", e);
        }
        return name;
    }

    @Override
    public byte[] load(String path) {
        try {
            return Files.readAllBytes(resolve(path));
        } catch (IOException e) {
            throw new UncheckedIOException("채팅 사진을 읽지 못했습니다: " + path, e);
        }
    }

    @Override
    public void delete(String path) {
        try {
            Files.deleteIfExists(resolve(path));
        } catch (IOException e) {
            throw new UncheckedIOException("채팅 사진을 지우지 못했습니다: " + path, e);
        }
    }

    /** 저장 폴더 안의 경로로 바꾼다. 정규화한 결과가 폴더 밖이면(../ 등) 거부한다. */
    private Path resolve(String path) {
        Path resolved = root.resolve(path).normalize();
        if (!resolved.startsWith(root) || resolved.equals(root)) {
            throw new IllegalArgumentException("저장 폴더 밖의 경로입니다: " + path);
        }
        return resolved;
    }
}
