package com.travelfootsteps.chat;

/** 메시지 종류. DB와 API에 이 이름 그대로 저장·전송된다. */
public enum MessageType {
    TEXT,
    /** 사진 메시지 (Plan D Task 6). 이미지 경로 컬럼은 V13에서 추가된다. */
    IMAGE
}
