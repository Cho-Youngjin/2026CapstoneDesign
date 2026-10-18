package com.travelfootsteps.chat;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 그룹 채팅방 API (Plan D Task 1). 요청한 사람의 uid는 항상 인증 정보에서 꺼낸다 —
 * 요청 바디나 경로로 받은 uid는 믿지 않는다. 규칙은 전부 {@link RoomService}에 있다.
 */
@RestController
@RequestMapping("/api/rooms")
@RequiredArgsConstructor
public class RoomController {

    private final RoomService roomService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public RoomDetailResponse create(@Valid @RequestBody CreateRoomRequest request, Authentication authentication) {
        return roomService.createGroup(authentication.getName(), request.name());
    }

    @PostMapping("/join")
    public RoomDetailResponse join(@Valid @RequestBody JoinRoomRequest request, Authentication authentication) {
        return roomService.join(authentication.getName(), request.inviteCode());
    }

    @GetMapping
    public List<RoomSummaryResponse> myRooms(Authentication authentication) {
        return roomService.myRooms(authentication.getName());
    }

    @GetMapping("/{id}")
    public RoomDetailResponse detail(@PathVariable Long id, Authentication authentication) {
        return roomService.detail(authentication.getName(), id);
    }
}
