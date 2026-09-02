// Tongits 桌面区域统一透视 Shader。
// 四个放置区在同一张全屏画布中计算，避免每个 Control 围绕自身中心变形后方向不一致。
shader_type canvas_item;

uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec4 left_zone = vec4(0.12, 0.12, 0.24, 0.31);
uniform vec4 deck_zone = vec4(0.43, 0.12, 0.13, 0.16);
uniform vec4 right_zone = vec4(0.64, 0.12, 0.24, 0.31);
uniform vec4 player_zone = vec4(0.11, 0.48, 0.78, 0.13);

uniform float far_scale : hint_range(0.5, 1.0) = 0.70;
uniform float near_scale : hint_range(1.0, 1.4) = 1.18;
uniform float corner_radius_px : hint_range(0.0, 40.0) = 13.0;
uniform float border_width_px : hint_range(0.5, 8.0) = 2.0;
uniform vec4 border_color : source_color = vec4(0.38, 0.72, 1.0, 0.58);
uniform vec4 fill_color : source_color = vec4(0.07, 0.31, 0.68, 0.16);
// 中央抽牌/弃牌托盘使用独立深色底，其他牌组放置区继续保持轻量提示效果。
uniform vec4 deck_border_color : source_color = vec4(0.32, 0.55, 0.88, 0.36);
uniform vec4 deck_fill_color : source_color = vec4(0.035, 0.12, 0.29, 0.52);

float rounded_rect_distance(vec2 point_px, vec4 rect_uv) {
	vec2 center_px = (rect_uv.xy + rect_uv.zw * 0.5) * viewport_size;
	vec2 half_size_px = rect_uv.zw * viewport_size * 0.5;
	float radius = min(corner_radius_px, min(half_size_px.x, half_size_px.y));
	vec2 delta = abs(point_px - center_px) - (half_size_px - vec2(radius));
	return length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0) - radius;
}

vec4 draw_zone(vec2 table_uv, vec4 rect_uv, vec4 zone_fill_color, vec4 zone_border_color) {
	float distance_px = rounded_rect_distance(table_uv * viewport_size, rect_uv);
	float smoothing = max(fwidth(distance_px), 0.75);
	float inside = 1.0 - smoothstep(-smoothing, smoothing, distance_px);
	float inner = 1.0 - smoothstep(-smoothing, smoothing, distance_px + border_width_px);
	float border = clamp(inside - inner, 0.0, 1.0);
	return vec4(
		mix(zone_fill_color.rgb, zone_border_color.rgb, border),
		mix(zone_fill_color.a, zone_border_color.a, border) * inside
	);
}

void fragment() {
	// 先将屏幕坐标逆变换回桌面坐标，再绘制区域；因此所有区域共享同一个消失点。
	float depth_scale = mix(far_scale, near_scale, UV.y);
	vec2 table_uv = vec2(0.5 + (UV.x - 0.5) / depth_scale, UV.y);

	vec4 result = vec4(0.0);
	vec4 zone = draw_zone(table_uv, left_zone, fill_color, border_color);
	if (zone.a > 0.0) {
		result = zone;
	}
	zone = draw_zone(table_uv, deck_zone, deck_fill_color, deck_border_color);
	if (zone.a > 0.0) {
		result = zone;
	}
	zone = draw_zone(table_uv, right_zone, fill_color, border_color);
	if (zone.a > 0.0) {
		result = zone;
	}
	zone = draw_zone(table_uv, player_zone, fill_color, border_color);
	if (zone.a > 0.0) {
		result = zone;
	}
	COLOR = result;
}
