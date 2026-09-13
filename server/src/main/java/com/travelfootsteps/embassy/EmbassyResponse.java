package com.travelfootsteps.embassy;

// 응답 JSON 계약(Plan F가 가정하는 {id, type, name, lat, lng, phone, emergencyPhone, address})을
// 엔티티 구조 변경과 분리하기 위한 DTO.
public record EmbassyResponse(Long id, String type, String name, double lat, double lng,
                               String phone, String emergencyPhone, String address) {
    public static EmbassyResponse from(Embassy embassy) {
        return new EmbassyResponse(embassy.getId(), embassy.getType(), embassy.getName(),
                embassy.getLat(), embassy.getLng(), embassy.getPhone(),
                embassy.getEmergencyPhone(), embassy.getAddress());
    }
}
