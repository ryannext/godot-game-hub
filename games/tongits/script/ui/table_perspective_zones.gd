class_name TongitsTablePerspectiveZones
extends ColorRect

## 桌面透视必须以整张桌面为坐标系；这些节点只保留为编辑器中可拖动的布局标记。
@export var left_zone_path: NodePath
@export var deck_zone_path: NodePath
@export var right_zone_path: NodePath
@export var player_zone_path: NodePath

var _last_viewport_size := Vector2.ZERO
var _last_zone_rects: Array[Rect2] = []


func _ready() -> void:
	resized.connect(_sync_shader_regions)
	call_deferred("_sync_shader_regions")


func _process(_delta: float) -> void:
	# 编辑器或后续 UI 动画改变标记位置时自动同步，避免 Shader 再维护一份固定坐标。
	var current_rects := _collect_zone_rects()
	if size != _last_viewport_size or current_rects != _last_zone_rects:
		_sync_shader_regions()


func _sync_shader_regions() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null or size.x <= 0.0 or size.y <= 0.0:
		return

	var rects := _collect_zone_rects()
	if rects.size() != 4:
		return

	shader_material.set_shader_parameter("viewport_size", size)
	shader_material.set_shader_parameter("left_zone", _to_normalized_rect(rects[0]))
	shader_material.set_shader_parameter("deck_zone", _to_normalized_rect(rects[1]))
	shader_material.set_shader_parameter("right_zone", _to_normalized_rect(rects[2]))
	shader_material.set_shader_parameter("player_zone", _to_normalized_rect(rects[3]))
	_last_viewport_size = size
	_last_zone_rects = rects


func _collect_zone_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for path in [left_zone_path, deck_zone_path, right_zone_path, player_zone_path]:
		var marker := get_node_or_null(path) as Control
		if marker == null:
			return []
		result.append(marker.get_global_rect())
	return result


func _to_normalized_rect(global_rect: Rect2) -> Vector4:
	var local_origin := global_rect.position - global_position
	return Vector4(
		local_origin.x / size.x,
		local_origin.y / size.y,
		global_rect.size.x / size.x,
		global_rect.size.y / size.y
	)
