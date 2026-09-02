class_name TongitsDeckPileView
extends Control

const CARD_BACK_TEXTURE := preload("res://games/tongits/res/images/tip/card_back.png")
const PERSPECTIVE_SHADER := preload("res://games/tongits/assets/shaders/faux_3d_card.gdshader")
const CARD_SIZE := Vector2(67.2, 90.0)
const COUNT_BADGE_OFFSET := Vector2(15.6, 28.0)
const LAYER_OFFSET_Y := 1.0
# 13 张起始牌堆以中心对称展开，固定底边为 +6px；后续牌堆共用这条底边。
const STACK_BOTTOM_OFFSET_Y := 6.0
const BOTTOM_TINT := Color(0.62, 0.62, 0.68, 1.0)
const DECK_PERSPECTIVE_ROTATION_X := 16.0
const DECK_PERSPECTIVE_FOV := 72.0
const DISCARD_PERSPECTIVE_ROTATION_X := DECK_PERSPECTIVE_ROTATION_X
const DISCARD_PERSPECTIVE_FOV := DECK_PERSPECTIVE_FOV
const MAX_OFF_AXIS_ROTATION_Y := 30.0

@onready var count_badge: Control = $DeckCountBadge
@onready var count_label: Label = $DeckCountBadge/DeckCountLabel
@onready var draw_pile_anchor: Control = $DrawPileAnchor
@onready var discard_pile_anchor: Control = $DiscardPileAnchor

var _card_count := 0
var _discard_placeholder: TextureRect

func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_ensure_discard_placeholder()
	# 运行时按真实剩余数量生成牌背；场景文件不再保存固定的三层示意节点。
	set_card_count(0, false)

func set_card_count(card_count: int, show_count: bool) -> void:
	_card_count = maxi(0, card_count)
	_clear_card_layers()
	# 不同张数的牌堆都锚定在同一底边；15 张会比初始 13 张向上多延伸两层。
	var top_offset_y := 0.0
	if _card_count > 0:
		top_offset_y = STACK_BOTTOM_OFFSET_Y - LAYER_OFFSET_Y * (_card_count - 1)
	# 先创建最底层、最后创建顶层，利用兄弟绘制顺序让顶牌盖住下层牌。
	for depth in range(_card_count - 1, -1, -1):
		var card_back := TextureRect.new()
		card_back.name = "PileCard%02d" % depth
		card_back.position = draw_pile_anchor.position + Vector2(0.0, top_offset_y + LAYER_OFFSET_Y * depth)
		card_back.size = CARD_SIZE
		card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 每张牌都保留完整牌背并独立完成透视，然后再按 Y 轴顺序叠加。
		card_back.material = _create_perspective_material(
			DECK_PERSPECTIVE_ROTATION_X,
			DECK_PERSPECTIVE_FOV,
			_perspective_rotation_y_for(draw_pile_anchor, DECK_PERSPECTIVE_FOV)
		)
		# 牌背保持与 HandView 同层；按“底层先创建、顶层后创建”的兄弟顺序完成覆盖。
		card_back.z_index = 0
		card_back.modulate = _layer_tint(depth)
		add_child(card_back)
	count_badge.position = draw_pile_anchor.position + COUNT_BADGE_OFFSET + Vector2(0.0, top_offset_y)
	count_label.text = str(_card_count)
	count_badge.visible = show_count and _card_count > 0
	count_badge.z_index = _card_count + 1
	if is_instance_valid(_discard_placeholder):
		# 占位牌与抽牌堆最上层对齐，牌数变化时仍保持并排关系。
		_discard_placeholder.position = discard_pile_anchor.position + Vector2(0.0, top_offset_y)

func _create_perspective_material(
	rotation_x: float = DECK_PERSPECTIVE_ROTATION_X,
	camera_fov: float = DECK_PERSPECTIVE_FOV,
	rotation_y: float = 0.0
) -> ShaderMaterial:
	var perspective_material := ShaderMaterial.new()
	perspective_material.shader = PERSPECTIVE_SHADER
	perspective_material.set_shader_parameter(&"fov", camera_fov)
	perspective_material.set_shader_parameter(&"rot_x_deg", rotation_x)
	perspective_material.set_shader_parameter(&"rot_y_deg", rotation_y)
	perspective_material.set_shader_parameter(&"cull_backface", false)
	perspective_material.set_shader_parameter(&"use_front", true)
	perspective_material.set_shader_parameter(&"uv_rect", Vector4(0.0, 0.0, 1.0, 1.0))
	perspective_material.set_shader_parameter(&"item_size_px", CARD_SIZE)
	perspective_material.set_shader_parameter(&"inset", 0.0)
	return perspective_material

func _ensure_discard_placeholder() -> void:
	if is_instance_valid(_discard_placeholder):
		return
	# 当前业务流程尚未接入桌面弃牌数据，先保留一张牌背作为可替换的视觉入口。
	_discard_placeholder = TextureRect.new()
	_discard_placeholder.name = "DiscardPlaceholder"
	_discard_placeholder.position = discard_pile_anchor.position
	_discard_placeholder.size = CARD_SIZE
	_discard_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_placeholder.texture = CARD_BACK_TEXTURE
	_discard_placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_discard_placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_discard_placeholder.material = _create_perspective_material(
		DISCARD_PERSPECTIVE_ROTATION_X,
		DISCARD_PERSPECTIVE_FOV,
		_perspective_rotation_y_for(discard_pile_anchor, DISCARD_PERSPECTIVE_FOV)
	)
	_discard_placeholder.z_index = 1
	add_child(_discard_placeholder)

func _perspective_rotation_y_for(anchor: Control, camera_fov: float) -> float:
	# 使用同一台位于屏幕 X 中心的虚拟相机：左、右牌的离轴角度互为镜像，中心点严格为 0。
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 0.0
	var focal_length := viewport_size.y * 0.5 / tan(deg_to_rad(camera_fov) * 0.5)
	var card_center_x := anchor.global_position.x + CARD_SIZE.x * 0.5
	var offset_from_center := card_center_x - viewport_size.x * 0.5
	return clampf(
		-rad_to_deg(atan(offset_from_center / focal_length)),
		-MAX_OFF_AXIS_ROTATION_Y,
		MAX_OFF_AXIS_ROTATION_Y
	)

func _on_viewport_size_changed() -> void:
	# Control 锚点会在当前帧末尾完成重排，下一帧再读取全局位置。
	call_deferred("_refresh_off_axis_perspective")

func _refresh_off_axis_perspective() -> void:
	var draw_rotation_y := _perspective_rotation_y_for(draw_pile_anchor, DECK_PERSPECTIVE_FOV)
	for child in get_children():
		if child is TextureRect and child.name.begins_with("PileCard"):
			var pile_material := child.material as ShaderMaterial
			if pile_material != null:
				pile_material.set_shader_parameter(&"rot_y_deg", draw_rotation_y)
	if is_instance_valid(_discard_placeholder):
		var discard_material := _discard_placeholder.material as ShaderMaterial
		if discard_material != null:
			discard_material.set_shader_parameter(
				&"rot_y_deg",
				_perspective_rotation_y_for(discard_pile_anchor, DISCARD_PERSPECTIVE_FOV)
			)

func card_count() -> int:
	return _card_count

func _clear_card_layers() -> void:
	for child in get_children():
		if child is TextureRect and child.name.begins_with("PileCard"):
			remove_child(child)
			child.queue_free()

func _layer_tint(depth: int) -> Color:
	if _card_count <= 1:
		return Color.WHITE
	# 越靠下的牌稍暗，使每一层 1px 的边缘在相同牌背纹理下仍保持可辨识。
	var weight := float(depth) / float(_card_count - 1)
	return Color.WHITE.lerp(BOTTOM_TINT, weight)
