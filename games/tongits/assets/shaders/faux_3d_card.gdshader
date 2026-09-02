// Faux 3D Perspective Shader for 2D CanvasItems.
// Copyright (c) 2025 Kamiel de Visser (codevogel), MIT License.
// 来源：https://github.com/codevogel/faux-3d-perspective-shader-godot
// Tongits 仅使用 X 轴轻微倾斜表现桌面深度，不引入任何 3D 节点。
shader_type canvas_item;

uniform bool cull_backface = false;
uniform bool use_front = true;
uniform float fov : hint_range(1.0, 179.0) = 75.0;
uniform float rot_y_deg : hint_range(-360.0, 360.0) = 0.0;
uniform float rot_x_deg : hint_range(-360.0, 360.0) = 0.0;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 item_size_px = vec2(112.0, 150.0);
uniform float inset : hint_range(0.0, 1.0) = 0.0;

varying vec2 offset;
varying vec3 world_pos_3d;
varying vec4 vertex_tint;

void vertex() {
	// 将节点 tint 单独传入片元阶段，避免 TextureRect 的 COLOR 再次携带纹理采样结果。
	vertex_tint = COLOR;
	vec2 local_uv = (UV - uv_rect.xy) / uv_rect.zw;
	float rot_y_rad = radians(rot_y_deg);
	float rot_x_rad = radians(rot_x_deg);

	float sin_y = sin(rot_y_rad);
	float cos_y = cos(rot_y_rad);
	float sin_x = sin(rot_x_rad);
	float cos_x = cos(rot_x_rad);

	mat3 rotation_matrix;
	rotation_matrix[0] = vec3(cos_y, 0.0, -sin_y);
	rotation_matrix[1] = vec3(sin_y * sin_x, cos_x, cos_y * sin_x);
	rotation_matrix[2] = vec3(sin_y * cos_x, -sin_x, cos_y * cos_x);

	float perspective_scale = tan(radians(fov) * 0.5);
	world_pos_3d = rotation_matrix * vec3(local_uv - 0.5, 0.5 / perspective_scale);

	float depth_scale = (0.5 / perspective_scale) + 0.5;
	world_pos_3d.xy *= depth_scale * rotation_matrix[2].z;
	offset = depth_scale * rotation_matrix[2].xy;

	// 原版使用 1 / TEXTURE_PIXEL_SIZE；AtlasTexture 会把它解释成整张图集尺寸。
	// 显式使用单张牌尺寸后，顶点扩张与原算法一致，又不会被牌面图集放大数倍。
	VERTEX += (local_uv - 0.5) * item_size_px * perspective_scale * (1.0 - inset);
}

void fragment() {
	if (cull_backface && world_pos_3d.z <= 0.0) {
		discard;
	}
	vec2 projected_uv = (world_pos_3d.xy / world_pos_3d.z) - offset + 0.5;
	if (
		projected_uv.x < 0.0
		|| projected_uv.x > 1.0
		|| projected_uv.y < 0.0
		|| projected_uv.y > 1.0
	) {
		discard;
	}

	vec2 sample_uv = projected_uv;
	if (!use_front) {
		sample_uv.x = 1.0 - sample_uv.x;
	}
	sample_uv = uv_rect.xy + sample_uv * uv_rect.zw;
	// 只采样纹理一次；否则红色牌背会被平方乘色而变成高饱和纯红。
	// vertex_tint 仍保留节点 modulate，使发牌牌堆的逐层明暗继续有效。
	COLOR = texture(TEXTURE, sample_uv) * vertex_tint;
}
