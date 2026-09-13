package com.travelfootsteps.trip;

import org.springframework.data.jpa.repository.JpaRepository;

// JpaRepository<Trip, Long>을 상속만 하면 스프링 데이터 JPA가 실행 시점에 프록시 구현체를
// 자동으로 만들어준다. save(), findById() 같은 기본 CRUD만으로 이 API가 필요로 하는 것을 전부
// 충당할 수 있어서 별도 쿼리 메서드가 없다 — "이 사용자의 여행 목록"처럼 목록 조회를 하는
// 엔드포인트가 이번 계획(Plan A)에는 없다(단건 조회/생성/새로고침/완료 처리뿐).
public interface TripRepository extends JpaRepository<Trip, Long> {
}
