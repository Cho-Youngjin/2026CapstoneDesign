package com.travelfootsteps.chat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;

public interface AppUserRepository extends JpaRepository<AppUser, String> {

    /** 방 상세의 멤버 프로필을 한 번에 가져온다(멤버마다 따로 조회하지 않기 위해). */
    List<AppUser> findByFirebaseUidIn(Collection<String> firebaseUids);
}
