/// 자주 쓰는 문구를 4개 상황으로 분류한다.
enum PresetCategory {
  immigration,
  restaurant,
  transport,
  emergency,
}

extension PresetCategoryLabel on PresetCategory {
  String get labelKo {
    switch (this) {
      case PresetCategory.immigration:
        return '입국심사';
      case PresetCategory.restaurant:
        return '식당';
      case PresetCategory.transport:
        return '교통';
      case PresetCategory.emergency:
        return '응급상황';
    }
  }
}

/// 미리 준비해둔 한국어 문구 하나. 버튼을 누르면 이 textKo가 번역 요청으로 들어간다.
class PhrasePreset {
  const PhrasePreset(this.category, this.textKo);

  final PresetCategory category;
  final String textKo;
}

/// 카테고리당 4개씩, 총 16개의 자주 쓰는 문구.
const kPhrasePresets = <PhrasePreset>[
  // 입국심사
  PhrasePreset(PresetCategory.immigration, '여권 보여드릴게요'),
  PhrasePreset(PresetCategory.immigration, '여행 목적은 관광입니다'),
  PhrasePreset(PresetCategory.immigration, '일주일 동안 머무를 예정입니다'),
  PhrasePreset(PresetCategory.immigration, '숙소 예약 확인서입니다'),

  // 식당
  PhrasePreset(PresetCategory.restaurant, '메뉴판 좀 보여주세요'),
  PhrasePreset(PresetCategory.restaurant, '이거 하나 주세요'),
  PhrasePreset(PresetCategory.restaurant, '카드로 결제할 수 있나요?'),
  PhrasePreset(PresetCategory.restaurant, '계산서 주세요.'),

  // 교통
  PhrasePreset(PresetCategory.transport, '이 주소로 가주세요'),
  PhrasePreset(PresetCategory.transport, '여기서 가장 가까운 역이 어디예요?'),
  PhrasePreset(PresetCategory.transport, '표는 어디서 사나요?'),
  PhrasePreset(PresetCategory.transport, '이 버스가 공항으로 가나요?'),

  // 응급상황
  PhrasePreset(PresetCategory.emergency, '도와주세요'),
  PhrasePreset(PresetCategory.emergency, '병원이 어디 있나요?'),
  PhrasePreset(PresetCategory.emergency, '지갑을 잃어버렸어요'),
  PhrasePreset(PresetCategory.emergency, '경찰을 불러주세요'),
];