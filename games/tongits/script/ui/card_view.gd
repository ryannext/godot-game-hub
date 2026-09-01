class_name TongitsCardView
extends TextureRect

const CARD_BACK_TEXTURE := preload("res://games/tongits/res/images/tip/card_back.png")

# CardView 只识别短按与长按手势；选择集合和投放语义由 HandView 统一管理。
signal tapped(card_id: int)
signal drag_started(card_id: int, pointer_global: Vector2)
signal drag_moved(card_id: int, pointer_global: Vector2)
signal drag_ended(card_id: int, pointer_global: Vector2)
signal interaction_cancelled(card_id: int)

const LONG_PRESS_SECONDS := 0.38
# 指针移动达到 4px 即进入拖拽；静止时仍可通过长按进入拖拽。
const DRAG_START_DISTANCE := 4.0

var card_id := -1
var _front_texture: Texture2D
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
	set_process(false)

func setup(card: TongitsCard) -> void:
	card_id = card.card_id
	_front_texture = TongitsCardArtLibrary.texture_for(card)
	texture = _front_texture
	tooltip_text = card.display_name()

func show_back() -> void:
	# 发牌移动阶段统一显示牌背，牌面内容只在落位后的翻牌中出现。
	texture = CARD_BACK_TEXTURE

func show_front() -> void:
	if _front_texture != null:
		texture = _front_texture

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
