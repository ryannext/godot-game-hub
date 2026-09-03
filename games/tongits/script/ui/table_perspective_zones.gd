@tool
class_name TongitsTablePerspectiveZones
extends Control

## 区域节点只定义尺寸和位置；本节点用代码绘制样式，材质只执行统一桌面透视。
@export var left_zone_path: NodePath
@export var deck_zone_path: NodePath
@export var right_zone_path: NodePath
@export var player_zone_path: NodePath

@export_group("普通牌组区域")
@export var zone_fill_color := Color(0.07, 0.31, 0.68, 0.16)
@export var zone_border_color := Color(0.38, 0.72, 1.0, 0.58)

@export_group("中央牌堆区域")
@export var deck_fill_color := Color(0.035, 0.12, 0.29, 0.52)
@export var deck_border_color := Color(0.32, 0.55, 0.88, 0.36)

@export_group("区域外观")
@export_range(0.0, 40.0, 1.0) var corner_radius_px := 13.0
@export_range(0.0, 8.0, 1.0) var border_width_px := 2.0

var _last_viewport_size := Vector2.ZERO
var _last_zone_rects: Array[Rect2] = []


func _ready() -> void:
	resized.connect(_sync_regions)
	call_deferred("_sync_regions")


func _process(_delta: float) -> void:
	# 编辑器拖动区域节点后立即刷新，运行时布局动画也沿用同一套坐标。
	var current_rects := _collect_zone_rects()
	if size != _last_viewport_size or current_rects != _last_zone_rects:
		_sync_regions()


func _draw() -> void:
	var rects := _collect_zone_rects()
	if rects.size() != 4:
		return
	_draw_rounded_zone(_to_local_rect(rects[0]), zone_fill_color, zone_border_color)
	_draw_rounded_zone(_to_local_rect(rects[1]), deck_fill_color, deck_border_color)
	_draw_rounded_zone(_to_local_rect(rects[2]), zone_fill_color, zone_border_color)
	_draw_rounded_zone(_to_local_rect(rects[3]), zone_fill_color, zone_border_color)


func _sync_regions() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rects := _collect_zone_rects()
	if rects.size() != 4:
		return
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("viewport_size", size)
	_last_viewport_size = size
	_last_zone_rects = rects
	queue_redraw()


func _collect_zone_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for path in [left_zone_path, deck_zone_path, right_zone_path, player_zone_path]:
		var marker := get_node_or_null(path) as Control
		if marker == null:
			return []
		result.append(marker.get_global_rect())
	return result


func _to_local_rect(global_rect: Rect2) -> Rect2:
	return Rect2(global_rect.position - global_position, global_rect.size)


func _draw_rounded_zone(rect: Rect2, fill_color: Color, border_color: Color) -> void:
	var points := _rounded_rect_points(rect, corner_radius_px)
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill_color)
	if border_width_px > 0.0:
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, border_color, border_width_px, true)


func _rounded_rect_points(rect: Rect2, requested_radius: float) -> PackedVector2Array:
	# 单个连续多边形可确保顶点 Shader 对整块区域统一变形，不产生 StyleBox 九宫格分片。
	var radius := minf(requested_radius, minf(rect.size.x, rect.size.y) * 0.5)
	if radius <= 0.0:
		return PackedVector2Array([
			rect.position,
			rect.position + Vector2(rect.size.x, 0.0),
			rect.end,
			rect.position + Vector2(0.0, rect.size.y),
		])
	var points := PackedVector2Array()
	var corner_centers: Array[Vector2] = [
		rect.position + Vector2(radius, radius),
		rect.position + Vector2(rect.size.x - radius, radius),
		rect.end - Vector2(radius, radius),
		rect.position + Vector2(radius, rect.size.y - radius),
	]
	var start_angles: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	const CORNER_SEGMENTS := 8
	for corner_index in range(4):
		for segment_index in range(CORNER_SEGMENTS + 1):
			var angle: float = start_angles[corner_index] + PI * 0.5 * float(segment_index) / float(CORNER_SEGMENTS)
			points.append(corner_centers[corner_index] + Vector2(cos(angle), sin(angle)) * radius)
	return points
