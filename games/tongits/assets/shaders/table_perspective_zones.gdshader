// 桌面区域只负责统一的顶点透视；尺寸、颜色、边框和圆角均由 GDScript 绘制。
shader_type canvas_item;

uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float far_scale : hint_range(0.5, 1.0) = 0.70;
uniform float near_scale : hint_range(1.0, 1.4) = 1.18;

void vertex() {
	float normalized_y = clamp(VERTEX.y / viewport_size.y, 0.0, 1.0);
	float depth_scale = mix(far_scale, near_scale, normalized_y);
	// 所有代码绘制的区域共用屏幕 X 中心，Shader 不参与任何样式生成。
	VERTEX.x = viewport_size.x * 0.5 + (VERTEX.x - viewport_size.x * 0.5) * depth_scale;
}
