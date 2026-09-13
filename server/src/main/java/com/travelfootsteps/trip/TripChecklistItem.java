package com.travelfootsteps.trip;

import com.travelfootsteps.country.ChecklistTemplate;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

// @Entity + @Table(name = "trip_checklist"): trip_checklist 테이블(V8__trip_checklist.sql)의
// 한 행과 매핑되는 JPA 엔티티다. 여행이 삭제되면(ON DELETE CASCADE 덕분에) 이 행들도 DB
// 레벨에서 함께 삭제된다 — trip_task와 완전히 같은 생애주기다.
//
// 이 테이블의 각 행은 국가 공통(또는 국가 전용) checklist_template 행을 "복사"한 스냅샷이다.
// TripController.create()가 여행을 만드는 시점에 fromTemplate()로 딱 한 번 복사해서 저장하고,
// 그 뒤로는 checklist_template이 어떻게 바뀌든 이 행들을 다시 동기화하지 않는다 — trip 테이블의
// 판정 스냅샷(Trip.applyJudgementSnapshot 문서 참고)과 완전히 같은 이유다: 관리자가 나중에
// 공통 템플릿 문구를 고치거나 항목을 추가/삭제해도, 이미 여행을 만들어 체크 진행 중인
// 사용자의 목록이 조용히 바뀌면 안 된다. 대신 checked 컬럼은 (판정 스냅샷과 달리) 이 테이블
// 자체가 갖는 사용자 상태이므로, 새로고침 없이 POST .../check 요청만으로 계속 갱신된다.
@Entity
@Table(name = "trip_checklist")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TripChecklistItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "trip_id", nullable = false)
    private Long tripId;

    @Column(nullable = false, length = 30)
    private String category;

    @Column(nullable = false, length = 100)
    private String title;

    @Column(length = 255)
    private String description;

    @Column(nullable = false)
    private int priority;

    @Column(nullable = false)
    private boolean checked;

    // checklist_template 한 행을 이 여행(tripId) 소유의 새 스냅샷 행으로 복사한다. id는
    // 복사하지 않는다 — trip_checklist.id는 이 테이블 자체의 독립적인 시퀀스이기 때문이다.
    public static TripChecklistItem fromTemplate(Long tripId, ChecklistTemplate template) {
        TripChecklistItem item = new TripChecklistItem();
        item.tripId = tripId;
        item.category = template.getCategory();
        item.title = template.getTitle();
        item.description = template.getDescription();
        item.priority = template.getPriority();
        item.checked = false;
        return item;
    }

    // 체크/체크 해제 둘 다 이 메서드 하나로 처리한다 — POST .../check 요청 바디의
    // {checked: boolean} 값을 그대로 반영하면 되므로, done()처럼 한쪽 방향만 여는 메서드
    // (TripTask.markDone() 참고)가 아니라 양방향 setter 형태가 더 맞는다.
    public void applyChecked(boolean checked) {
        this.checked = checked;
    }
}
