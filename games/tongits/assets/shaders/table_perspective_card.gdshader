// Meld 卡牌使用与桌面区域背景完全相同的全局 X 中心透视。
shader_type canvas_item;
render_mode skip_vertex_transform;

uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float far_scale : hint_range(0.5, 1.0) = 0.85;
uniform float near_scale : hint_range(1.0, 1.4) = 1.09;
uniform float perspective_strength : hint_range(0.0, 1.0) = 1.0;
uniform float item_center_y_px = 0.0;

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
	vec2 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float normalized_y = clamp(world_vertex.y / viewport_size.y, 0.0, 1.0);
	float depth_scale = mix(far_scale, near_scale, normalized_y);
	float center_normalized_y = clamp(item_center_y_px / viewport_size.y, 0.0, 1.0);
	float center_depth_scale = mix(far_scale, near_scale, center_normalized_y);
	float full_perspective_x = viewport_size.x * 0.5 + (world_vertex.x - viewport_size.x * 0.5) * depth_scale;
	float center_plane_x = viewport_size.x * 0.5 + (world_vertex.x - viewport_size.x * 0.5) * center_depth_scale;
	world_vertex.x = mix(center_plane_x, full_perspective_x, perspective_strength);
	VERTEX = world_vertex;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * vertex_tint;
}
