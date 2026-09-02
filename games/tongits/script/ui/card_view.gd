class_name TongitsCardView
extends TextureRect

const CARD_BACK_TEXTURE := preload("res://games/tongits/res/images/tip/card_back.png")
const PERSPECTIVE_SHADER := preload("res://games/tongits/assets/shaders/faux_3d_card.gdshader")

# CardView 只识别短按与长按手势；选择集合和投放语义由 HandView 统一管理。
signal tapped(card_id: int)
signal drag_started(card_id: int, pointer_global: Vector2)
signal drag_moved(card_id: int, pointer_global: Vector2)
signal drag_ended(card_id: int, pointer_global: Vector2)
signal interaction_cancelled(card_id: int)

const LONG_PRESS_SECONDS := 0.38
# 指针移动达到 4px 即进入拖拽；静止时仍可通过长按进入拖拽。
const DRAG_START_DISTANCE := 4.0
const DEFAULT_PERSPECTIVE_FOV := 75.0

var card_id := -1
var _front_texture: Texture2D
var perspective_rotation_x := 0.0:
	set(value):
		perspective_rotation_x = value
		_set_shader_parameter(&"rot_x_deg", value)
var selected := false:
	set(value):
		selected = value
		queue_redraw()

# 由 HandView 的统一调试开关控制，仅在排查点击与牌组范围时显示选中描边。
var show_debug_outline := false:
	set(value):
		show_debug_outline = value
		queue_redraw()

var _pressed := false
var _dragging := false
var _touch_index := -1
var _press_started_msec := 0
var _press_global := Vector2.ZERO
var _last_global := Vector2.ZERO

func _init() -> void:
	custom_minimum_size = Vector2(112, 150)
	size = Vector2(112, 150)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 每张牌持有独立材质；发牌和拖拽插值参数时不会连带改变其他卡牌。
	var perspective_material := ShaderMaterial.new()
	perspective_material.shader = PERSPECTIVE_SHADER
	material = perspective_material
	_set_shader_parameter(&"fov", DEFAULT_PERSPECTIVE_FOV)
	_set_shader_parameter(&"rot_y_deg", 0.0)
	_set_shader_parameter(&"rot_x_deg", perspective_rotation_x)
	_set_shader_parameter(&"cull_backface", false)
	_set_shader_parameter(&"use_front", true)
	_set_shader_parameter(&"item_size_px", size)
	_set_shader_parameter(&"inset", 0.0)
	set_process(false)

func set_perspective(rotation_x_degrees: float, camera_fov: float = DEFAULT_PERSPECTIVE_FOV) -> void:
	# 只改变视觉投影；Control 的位置、尺寸和业务坐标保持不变。
	_set_shader_parameter(&"fov", camera_fov)
	perspective_rotation_x = rotation_x_degrees

func _set_shader_parameter(parameter: StringName, value: Variant) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(parameter, value)

func setup(card: TongitsCard) -> void:
	card_id = card.card_id
	_front_texture = TongitsCardArtLibrary.texture_for(card)
	texture = _front_texture
	_sync_shader_texture_region()
	tooltip_text = card.display_name()

func show_back() -> void:
	# 发牌移动阶段统一显示牌背，牌面内容只在落位后的翻牌中出现。
	texture = CARD_BACK_TEXTURE
	_sync_shader_texture_region()

func show_front() -> void:
	if _front_texture != null:
		texture = _front_texture
		_sync_shader_texture_region()

func _sync_shader_texture_region() -> void:
	var uv_region := Vector4(0.0, 0.0, 1.0, 1.0)
	if texture is AtlasTexture:
		var atlas_texture := texture as AtlasTexture
		if atlas_texture.atlas != null:
			var atlas_size := atlas_texture.atlas.get_size()
			if atlas_size.x > 0.0 and atlas_size.y > 0.0:
				uv_region = Vector4(
					atlas_texture.region.position.x / atlas_size.x,
					atlas_texture.region.position.y / atlas_size.y,
					atlas_texture.region.size.x / atlas_size.x,
					atlas_texture.region.size.y / atlas_size.y
				)
	_set_shader_parameter(&"uv_rect", uv_region)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and _pressed and event.index == _touch_index:
		_handle_pointer_move(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_press(event.global_position, -1)
		elif _pressed:
			# 只接收由本卡牌开始的鼠标释放，避免悬停卡牌收到孤立 release 后被误选。
			_end_press(event.global_position)
	elif event is InputEventMouseMotion and _pressed and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_handle_pointer_move(event.global_position)

func _process(_delta: float) -> void:
	if not _pressed or _dragging:
		return
	var elapsed := float(Time.get_ticks_msec() - _press_started_msec) / 1000.0
	if elapsed >= LONG_PRESS_SECONDS:
		_start_drag()

func cancel_interaction() -> void:
	_pressed = false
	_dragging = false
	_touch_index = -1
	set_process(false)

func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or not _pressed:
		return
	var was_dragging := _dragging
	cancel_interaction()
	if was_dragging:
		# 窗口失焦不会产生可靠的 release，通知 HandView 回收拖拽占位与层级状态。
		interaction_cancelled.emit(card_id)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_begin_press(event.position, event.index)
	elif _pressed and event.index == _touch_index:
		_end_press(event.position)

func _begin_press(pointer_global: Vector2, pointer_index: int) -> void:
	if _pressed:
		return
	_pressed = true
	_dragging = false
	_touch_index = pointer_index
	_press_started_msec = Time.get_ticks_msec()
	_press_global = pointer_global
	_last_global = pointer_global
	set_process(true)

func _handle_pointer_move(pointer_global: Vector2) -> void:
	_last_global = pointer_global
	if not _dragging and pointer_global.distance_to(_press_global) >= DRAG_START_DISTANCE:
		_start_drag()
	if _dragging:
		drag_moved.emit(card_id, pointer_global)

func _start_drag() -> void:
	if not _pressed or _dragging:
		return
	_dragging = true
	drag_started.emit(card_id, _last_global)

func _end_press(pointer_global: Vector2) -> void:
	if _dragging:
		drag_ended.emit(card_id, pointer_global)
	else:
		tapped.emit(card_id)
	cancel_interaction()

func _draw() -> void:
	if selected and show_debug_outline:
		# 调试描边默认关闭；开启后可辅助确认卡牌的实际选中状态。
		draw_rect(Rect2(Vector2.ZERO, size), Color("9eeeff"), false, 4.0)
