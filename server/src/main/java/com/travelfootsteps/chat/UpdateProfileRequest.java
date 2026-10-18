package com.travelfootsteps.chat;

import jakarta.validation.constraints.Size;

/**
 * 프로필 올리기 요청. Firebase 계정에 이름이나 사진이 없을 수 있으므로 둘 다 null을 허용한다.
 * 길이 제한은 app_user 컬럼 크기(V11__chat.sql)와 같다.
 */
public record UpdateProfileRequest(
        @Size(max = 100) String displayName,
        @Size(max = 500) String photoUrl
) {
}
