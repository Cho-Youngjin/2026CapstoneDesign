package com.travelfootsteps.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

/**
 * 채팅 화면에 이름·사진을 띄우기 위한 프로필 캐시. 사용자의 원본은 Firebase Auth다.
 * 앱이 로그인 직후 {@code PUT /api/me/profile}로 올리며, 아직 올리지 않은 사용자는 행이 없다.
 */
@Entity
@Table(name = "app_user")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class AppUser {

    @Id
    @Column(name = "firebase_uid", length = 128)
    private String firebaseUid;

    @Column(name = "display_name", length = 100)
    private String displayName;

    @Column(name = "photo_url", length = 500)
    private String photoUrl;

    /** 푸시 알림(Plan D Task 8)용. 그 전까지는 항상 null. */
    @Column(name = "fcm_token", length = 500)
    private String fcmToken;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    public static AppUser create(String firebaseUid, String displayName, String photoUrl) {
        AppUser user = new AppUser();
        user.firebaseUid = firebaseUid;
        user.updateProfile(displayName, photoUrl);
        return user;
    }

    /** 프로필을 통째로 덮어쓴다 — 앱은 매 로그인마다 Firebase의 현재 값을 그대로 올린다. */
    public void updateProfile(String displayName, String photoUrl) {
        this.displayName = displayName;
        this.photoUrl = photoUrl;
        this.updatedAt = OffsetDateTime.now();
    }
}
