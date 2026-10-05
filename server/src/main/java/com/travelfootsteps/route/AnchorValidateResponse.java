package com.travelfootsteps.route;

// 통과(도로 50m 이내)하면 ok=true와 도로 위로 붙인 좌표, 아니면 ok=false와 snapped=null.
public record AnchorValidateResponse(boolean ok, GeoPoint snapped) {
}
