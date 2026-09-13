package com.travelfootsteps.country;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

// @Entity + @Table(name = "checklist_template"): checklist_template 테이블(V5__checklist_template.sql)의
// 한 행과 매핑되는 JPA 엔티티다. countryId가 null인 행은 모든 국가에 공통으로 적용되는 준비물
// 항목이고, countryId가 채워진 행은 그 국가 전용 항목이다(이 계획서 범위에서는 시드 데이터가
// 전부 공통 항목뿐이라 실제로는 항상 null이지만, R4가 이후 국가별 항목을 추가할 수 있도록
// 컬럼/엔티티는 처음부터 지원해 둔다).
@Entity
@Table(name = "checklist_template")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ChecklistTemplate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "country_id")
    private Long countryId;

    @Column(nullable = false, length = 30)
    private String category;

    @Column(nullable = false, length = 100)
    private String title;

    @Column(length = 255)
    private String description;

    @Column(nullable = false)
    private int priority;
}
