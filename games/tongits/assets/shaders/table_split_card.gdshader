// 中央牌区的左右半区投影。
// pivot_x=1 表示固定右侧内边，只拉伸左侧外边；pivot_x=0 则固定左侧内边，只拉伸右侧外边。
shader_type canvas_item;

uniform vec2 item_size_px = vec2(67.2, 90.0);
uniform float pivot_x : hint_range(0.0, 1.0) = 0.5;
uniform float far_scale : hint_range(0.5, 1.0) = 0.94;
uniform float near_scale : hint_range(1.0, 1.5) = 1.06;

void vertex() {
	float horizontal_scale = mix(far_scale, near_scale, UV.y);
	// 内侧切分边是公共透视轴，因此保持不动；位移只随到外边的距离增加。
	VERTEX.x += (UV.x - pivot_x) * item_size_px.x * (horizontal_scale - 1.0);
}
