package com.travelfootsteps.chat;

import java.util.Optional;

/**
 * 채팅에 올릴 수 있는 사진 형식 (Plan D Task 6).
 *
 * <p>형식은 <b>파일 앞부분 바이트(매직 넘버)</b>로 판정한다. 파일 이름의 확장자나 요청의 Content-Type은
 * 보내는 쪽이 마음대로 정할 수 있어 믿지 않는다 — 텍스트·HTML을 ".jpg"로 위장해 올리면 내려받는 쪽에서
 * 엉뚱한 내용이 열릴 수 있다.
 */
enum ChatImageFormat {
    JPEG("image/jpeg", "jpg"),
    PNG("image/png", "png"),
    WEBP("image/webp", "webp");

    final String contentType;
    final String extension;

    ChatImageFormat(String contentType, String extension) {
        this.contentType = contentType;
        this.extension = extension;
    }

    /** 지원하는 형식이면 그 형식, 아니면 빈 값. */
    static Optional<ChatImageFormat> detect(byte[] bytes) {
        if (startsWith(bytes, 0, 0xFF, 0xD8, 0xFF)) {
            return Optional.of(JPEG);
        }
        if (startsWith(bytes, 0, 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A)) {
            return Optional.of(PNG);
        }
        // WEBP는 "RIFF" + 파일 크기 4바이트 + "WEBP"로 시작한다. RIFF만 보면 WAV 같은 다른 형식도 걸린다.
        if (startsWith(bytes, 0, 'R', 'I', 'F', 'F') && startsWith(bytes, 8, 'W', 'E', 'B', 'P')) {
            return Optional.of(WEBP);
        }
        return Optional.empty();
    }

    /** 저장할 때 붙인 확장자로 형식을 되찾는다(내려받기 응답의 Content-Type). */
    static Optional<ChatImageFormat> fromExtension(String path) {
        for (ChatImageFormat format : values()) {
            if (path.endsWith("." + format.extension)) {
                return Optional.of(format);
            }
        }
        return Optional.empty();
    }

    private static boolean startsWith(byte[] bytes, int offset, int... expected) {
        if (bytes.length < offset + expected.length) {
            return false;
        }
        for (int i = 0; i < expected.length; i++) {
            if ((bytes[offset + i] & 0xFF) != expected[i]) {
                return false;
            }
        }
        return true;
    }
}
