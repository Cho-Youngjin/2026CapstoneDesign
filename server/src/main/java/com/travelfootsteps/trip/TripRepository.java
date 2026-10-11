package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TripRepository extends JpaRepository<Trip, Long> {

    // Spring Data JPA는 메서드 이름을 해석해 쿼리를 자동으로 만든다(쿼리 메서드). 이 이름은
    // "WHERE firebase_uid = ? ORDER BY depart_date DESC"가 된다 — 구현 클래스를 직접 쓰지 않아도
    // 스프링이 실행 시점에 프록시 구현체를 만들어 빈으로 등록한다.
    List<Trip> findByFirebaseUidOrderByDepartDateDesc(String firebaseUid);
}
