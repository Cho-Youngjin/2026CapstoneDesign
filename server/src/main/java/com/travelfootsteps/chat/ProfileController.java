package com.travelfootsteps.chat;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 내 프로필 올리기. 앱이 로그인할 때마다 Firebase 계정의 현재 이름·사진을 그대로 올린다
 * (Plan D Task 3). 처음이면 만들고, 있으면 덮어쓴다(upsert) — 그래서 POST가 아니라 PUT이다.
 */
@RestController
@RequestMapping("/api/me")
@RequiredArgsConstructor
public class ProfileController {

    private final AppUserRepository userRepository;

    @Transactional
    @PutMapping("/profile")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void updateProfile(@Valid @RequestBody UpdateProfileRequest request, Authentication authentication) {
        String uid = authentication.getName();
        userRepository.findById(uid).ifPresentOrElse(
                user -> user.updateProfile(request.displayName(), request.photoUrl()),
                () -> userRepository.save(AppUser.create(uid, request.displayName(), request.photoUrl())));
    }
}
