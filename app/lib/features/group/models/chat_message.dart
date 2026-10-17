/// 서버 `chat/MessageType.java`의 값과 문자 그대로 일치해야 한다.
enum MessageType {
  text('TEXT'),
  image('IMAGE');

  const MessageType(this.wireValue);

  final String wireValue;

  /// 모르는 값은 텍스트로 본다 — 앱이 죽지 않고 본문이라도 보여주게.
  static MessageType fromWire(String? value) =>
      MessageType.values.firstWhere((t) => t.wireValue == value, orElse: () => MessageType.text);
}

/// 채팅 메시지 하나. REST 응답(보내기·목록)과 STOMP 실시간 수신이 같은 모양이다
/// (서버 `chat/MessageResponse.java`, docs/api-spec.md 10절). 같은 메시지가 두 경로로
/// 올 수 있으므로 화면에서는 [id]로 중복을 걸러낸다.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderUid,
    required this.type,
    this.text,
    this.imageUrl,
    required this.createdAt,
  });

  /// 서버가 매기는 단조 증가값. 정렬과 "이 id보다 오래된 것" 페이지 조회의 기준이다.
  final int id;
  final int roomId;
  final String senderUid;
  final MessageType type;
  final String? text;

  /// 사진 메시지(Plan D Task 6) 전까지 항상 null.
  final String? imageUrl;

  /// 서버 시각(오프셋 포함)을 그대로 파싱한 값. 화면에 쓸 때는 toLocal()로 바꾼다.
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        roomId: json['roomId'] as int,
        senderUid: json['senderUid'] as String,
        type: MessageType.fromWire(json['type'] as String?),
        text: json['text'] as String?,
        imageUrl: json['imageUrl'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
