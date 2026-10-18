package com.travelfootsteps.chat;

/** 채팅방 종류. DB와 API에 이 이름 그대로("GROUP", "DM") 저장·전송된다. */
public enum RoomType {
    /** 초대 코드로 모이는 여행 그룹. 이름과 초대 코드가 있다. */
    GROUP,
    /** 같은 그룹에 속한 두 사람의 1:1 대화 (Plan D Task 5). */
    DM
}
