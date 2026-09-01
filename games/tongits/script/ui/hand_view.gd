class_name TongitsHandView
extends Control

class GroupVisualState:
	extends RefCounted
	var rect := Rect2()
	var target_rect := Rect2()
	var opacity := 1.0
	var target_opacity := 1.0
	var label := ""
	var group_type := TongitsMeldRules.GroupType.INVALID
	var color := Color.WHITE

signal selection_changed(loose_card_ids: Array, selected_group_id: int)
signal move_card_requested(card_id: int, target_area: StringName, target_group_id: int, target_index: int)

const CARD_VIEW_SCRIPT := preload("res://games/tongits/script/ui/card_view.gd")
const GROUP_BADGE_OVERLAY_SCRIPT := preload("res://games/tongits/script/ui/group_badge_overlay.gd")
const CARD_SIZE := Vector2(112, 150)
const MAX_CARD_STEP := 68.0
const MIN_CARD_STEP := 38.0
# 组边界的额外步长必须大于常规 44px 重叠量，才能在组牌与散牌之间留下可见空隙。
const GROUP_GAP := 64.0
const SELECTED_OFFSET := 28.0
# 拖拽占位左右各一张牌轻微抬起，形成托住拖拽牌的视觉凹槽，但不抢过选中态的高度。
const DRAG_NEIGHBOR_LIFT := 10.0
const HAND_MARGIN := 28.0
const PLACEHOLDER_ID := -9999
const GROUP_BADGE_HEIGHT := 28.0
const GROUP_BADGE_BOTTOM_INSET := 0.0
const LAYOUT_ANIMATION_SECONDS := 0.22
const ARRANGE_COLLAPSE_SECONDS := 0.18
const ARRANGE_EXPAND_SECONDS := 0.26
const DEAL_CARD_ANIMATION_SECONDS := 0.22
const DEAL_CARD_STAGGER_SECONDS := 0.075
const DEAL_Z_SWITCH_SECONDS := 0.075
const DEAL_START_SCALE := 0.6
const DEAL_REVEAL_MIN_SCALE := 0.7
const DEAL_REVEAL_SHRINK_SECONDS := 0.05
const DEAL_FACE_GROW_SECONDS := 0.10

@export_category("调试显示")
# 默认隐藏牌组范围和选中牌描边；需要检查命中、分组时可在 Inspector 中临时开启。
@export var show_debug_outlines := false:
	set(value):
		show_debug_outlines = value
		for view: TongitsCardView in _card_views.values():
			view.show_debug_outline = value
		queue_redraw()

@export_category("发牌动画")
# 优先读取场景内牌堆节点的实时中心，方便直接在编辑器里调整发牌位置。
@export var deal_origin_node_path := NodePath("../DeckArea")
# 节点不存在时才使用视口比例兜底，避免独立测试 HandView 时无法发牌。
@export var deal_origin_viewport_ratio := Vector2(0.5, 0.39)

@export_category("手牌布局")
# 默认让卡牌中心严格对齐 HandView 矩形中心；仅在美术需要微调时修改此偏移。
@export var hand_center_offset_y := 0.0

var _cards: Dictionary = {}
var _card_views: Dictionary = {}
var _groups: Array[Dictionary] = []
var _loose_card_ids: Array[int] = []
var _selected_loose_ids: Array[int] = []
var _selected_group_id := -1
var _sort_mode := TongitsHandServerSimulator.SortMode.RANK_SUIT

var _dragging_card_id := -1
var _preview_area: StringName = &""
var _preview_group_id := -1
var _preview_index := -1
var _drag_is_over_hand := false
var _last_layout: Dictionary = {}
var _drag_grab_offset := Vector2.ZERO
var _pending_move_card_id := -1
var _last_applied_revision := -1
var _deal_animation_pending := false
var _deal_cards_remaining := 0
var _arrange_animation_pending := false
var _arrange_cards_remaining := 0
# 记录每张牌的布局动画，开始拖拽或重新布局前必须停止旧动画，避免多个位置写入源互相争抢。
var _move_tweens: Dictionary = {}
var _move_targets: Dictionary = {}
var _group_badge_overlay: Control
var _group_visuals: Dictionary = {}
var _group_visual_tweens: Dictionary = {}

func _ready() -> void:
	clip_contents = false
	_group_badge_overlay = GROUP_BADGE_OVERLAY_SCRIPT.new()
	_group_badge_overlay.name = "GroupBadgeOverlay"
	_group_badge_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 普通牌最高约为几十层，拖拽牌为 1000；标识覆盖普通牌但不会盖住正在拖拽的牌。
	_group_badge_overlay.z_index = 900
	add_child(_group_badge_overlay)
	_group_badge_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(func(): _relayout(false))
	set_process(false)

func _process(_delta: float) -> void:
	# 父节点绘制的牌组外框和前景标识需要跟随子卡牌 Tween 的实时位置。
	_update_group_badges()
	queue_redraw()
	if not _has_active_layout_tweens():
		set_process(false)

func apply_snapshot(snapshot: Dictionary) -> void:
	var revision := int(snapshot.get("revision", -1))
	if revision >= 0 and _last_applied_revision >= 0 and revision < _last_applied_revision:
		# 网络模式下忽略迟到的旧快照，避免布局倒退并重新播放反向动画。
		return
	if revision >= 0:
		_last_applied_revision = revision
	var play_deal_animation := _deal_animation_pending
	var play_arrange_animation := _arrange_animation_pending
	_deal_animation_pending = false
	_arrange_animation_pending = false
	_cancel_deal_animation_runtime()
	_cancel_active_drag(false)
	_pending_move_card_id = -1
	_set_card_interaction_enabled(true)
	_groups.assign(snapshot.get("groups", []))
	_loose_card_ids.assign(snapshot.get("loose_card_ids", []))
	_sort_mode = int(snapshot.get("sort_mode", TongitsHandServerSimulator.SortMode.RANK_SUIT)) as TongitsHandServerSimulator.SortMode
	_cards.clear()
	for card_data: Dictionary in snapshot.get("cards", []):
		var card := TongitsCard.new(
			int(card_data.suit),
			int(card_data.rank),
			int(card_data.card_id)
		)
		_cards[card.card_id] = card
	_sync_card_views()
	_validate_selection()
	if play_deal_animation:
		_relayout_deal()
	elif play_arrange_animation:
		_relayout_collapse_expand()
	else:
		_relayout(true)

func prepare_deal_animation() -> void:
	# 下一份权威快照将被视为一次完整发牌，而不是普通排序或拖拽重排。
	_cancel_active_drag(false)
	_pending_move_card_id = -1
	_deal_animation_pending = true
	_set_card_interaction_enabled(false)

func prepare_arrange_animation() -> void:
	# 下一份快照会改变组合结构；先保留当前牌位，收到结果后统一收拢到中心再展开。
	_cancel_active_drag(false)
	_pending_move_card_id = -1
	_arrange_animation_pending = true
	_set_card_interaction_enabled(false)

func selected_loose_ids() -> Array[int]:
	return _selected_loose_ids.duplicate()

func selected_group_id() -> int:
	return _selected_group_id

func group_index(group_id: int) -> int:
	for index in _groups.size():
		if int(_groups[index].group_id) == group_id:
			return index
	return -1

func group_count() -> int:
	return _groups.size()

func clear_selection() -> void:
	_selected_loose_ids.clear()
	_selected_group_id = -1
	_update_selected_views()
	selection_changed.emit(_selected_loose_ids.duplicate(), -1)
	_relayout(true)

func _sync_card_views() -> void:
	for existing_id in _card_views.keys():
		if _cards.has(existing_id):
			continue
		_stop_card_tween(int(existing_id))
		_card_views[existing_id].queue_free()
		_card_views.erase(existing_id)
	for card_id in _cards:
		if _card_views.has(card_id):
			continue
		var view := CARD_VIEW_SCRIPT.new() as TongitsCardView
		view.setup(_cards[card_id])
		view.show_debug_outline = show_debug_outlines
		view.tapped.connect(_on_card_tapped)
		view.drag_started.connect(_on_card_drag_started)
		view.drag_moved.connect(_on_card_drag_moved)
		view.drag_ended.connect(_on_card_drag_ended)
		view.interaction_cancelled.connect(_on_card_interaction_cancelled)
		add_child(view)
		_card_views[card_id] = view
	_update_selected_views()

func _on_card_tapped(card_id: int) -> void:
	if _pending_move_card_id >= 0:
		return
	var group_id := _group_for_card(card_id)
	if group_id >= 0:
		_selected_loose_ids.clear()
		_selected_group_id = -1 if _selected_group_id == group_id else group_id
	else:
		_selected_group_id = -1
		if _selected_loose_ids.has(card_id):
			_selected_loose_ids.erase(card_id)
		else:
			_selected_loose_ids.append(card_id)
	_update_selected_views()
	selection_changed.emit(_selected_loose_ids.duplicate(), _selected_group_id)
	_relayout(true)

func _on_card_drag_started(card_id: int, pointer_global: Vector2) -> void:
	if _pending_move_card_id >= 0 or (_dragging_card_id >= 0 and _dragging_card_id != card_id):
		# HandView 只允许一个活动指针，避免多指拖拽互相覆盖 z_index 和预览状态。
		var rejected_view: TongitsCardView = _card_views.get(card_id)
		if rejected_view != null:
			rejected_view.cancel_interaction()
		return
	# 长按一旦成立便结束所有点击选择；拖拽单位永远只有当前这一张牌。
	var source := _location_for_card(card_id)
	var view: TongitsCardView = _card_views[card_id]
	# 保存鼠标在牌面内部的实际抓取点，拖拽开始时卡牌不会突然跳到鼠标上方。
	_drag_grab_offset = view.get_global_transform_with_canvas().affine_inverse() * pointer_global
	_stop_card_tween(card_id)
	_dragging_card_id = card_id
	_selected_loose_ids.clear()
	_selected_group_id = -1
	_update_selected_views()
	selection_changed.emit(_selected_loose_ids.duplicate(), -1)
	_preview_area = source.area
	_preview_group_id = source.group_id
	_preview_index = source.index
	_drag_is_over_hand = true
	view.z_index = 1000
	_position_dragged_view(pointer_global)
	_relayout(true)

func _on_card_drag_moved(card_id: int, pointer_global: Vector2) -> void:
	if card_id != _dragging_card_id:
		return
	_position_dragged_view(pointer_global)
	var local := _global_to_local(pointer_global)
	var was_over_hand := _drag_is_over_hand
	_drag_is_over_hand = _is_pointer_over_hand(local)
	var preview_changed := false
	if _drag_is_over_hand:
		preview_changed = _update_preview_slot(local.x)
	if preview_changed or was_over_hand != _drag_is_over_hand:
		# 只在预览插槽真正变化时重定向动画，避免每个鼠标事件都重建 Tween。
		_relayout(true)
	else:
		_update_group_badges()
		queue_redraw()

func _on_card_drag_ended(card_id: int, pointer_global: Vector2) -> void:
	if card_id != _dragging_card_id:
		return
	var local := _global_to_local(pointer_global)
	var valid_drop := _is_pointer_over_hand(local) and not _preview_area.is_empty()
	var target_area := _preview_area
	var target_group_id := _preview_group_id
	var target_index := _preview_index
	var view: TongitsCardView = _card_views[card_id]
	view.z_index = 0
	_dragging_card_id = -1
	_preview_area = &""
	_preview_group_id = -1
	_preview_index = -1
	_drag_is_over_hand = false
	_drag_grab_offset = Vector2.ZERO
	if valid_drop:
		# 先让拖拽牌落向预览插槽；同步快照会复用这条 Tween，异步时也不会悬停在鼠标松手处。
		_pending_move_card_id = card_id
		_set_card_interaction_enabled(false)
		_animate_pending_card_to_preview(card_id)
		move_card_requested.emit(card_id, target_area, target_group_id, target_index)
	else:
		_relayout(true)

func reject_pending_move() -> void:
	if _pending_move_card_id < 0:
		return
	_pending_move_card_id = -1
	_set_card_interaction_enabled(true)
	_relayout(true)

func _on_card_interaction_cancelled(card_id: int) -> void:
	if card_id == _dragging_card_id:
		_cancel_active_drag(true)

func _cancel_active_drag(animated: bool) -> void:
	if _dragging_card_id < 0:
		return
	var view: TongitsCardView = _card_views.get(_dragging_card_id)
	if view != null:
		view.z_index = 0
		view.cancel_interaction()
	_dragging_card_id = -1
	_preview_area = &""
	_preview_group_id = -1
	_preview_index = -1
	_drag_is_over_hand = false
	_drag_grab_offset = Vector2.ZERO
	if animated:
		_relayout(true)

func _animate_pending_card_to_preview(card_id: int) -> void:
	var view: TongitsCardView = _card_views.get(card_id)
	if view == null or _last_layout.is_empty():
		return
	var target := Vector2(
		float(_last_layout.placeholder_center_x) - CARD_SIZE.x * 0.5,
		_normal_card_y()
	)
	_stop_card_tween(card_id)
	if view.position.distance_to(target) <= 1.0:
		view.position = target
		return
	var tween := view.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", target, LAYOUT_ANIMATION_SECONDS)
	_move_tweens[card_id] = tween
	_move_targets[card_id] = target
	set_process(true)

func _set_card_interaction_enabled(enabled: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	for view: TongitsCardView in _card_views.values():
		view.mouse_filter = filter

func _is_pointer_over_hand(local: Vector2) -> bool:
	# 横纵方向都必须位于手牌容器附近，避免在屏幕远端松手仍吸附到最边缘插槽。
	return local.x >= 0.0 and local.x <= size.x and local.y >= -110.0 and local.y <= size.y + 40.0

func _position_dragged_view(pointer_global: Vector2) -> void:
	var local := _global_to_local(pointer_global)
	var view: TongitsCardView = _card_views[_dragging_card_id]
	# 保持按下点与鼠标重合，不再使用固定的向上偏移。
	view.position = local - _drag_grab_offset

func _update_preview_slot(drag_x: float) -> bool:
	var best_distance := INF
	var best_area: StringName = _preview_area
	var best_group_id := _preview_group_id
	var best_index := _preview_index

	for group: Dictionary in _groups:
		var group_id := int(group.group_id)
		var count := _card_ids_without_drag(group.card_ids).size()
		for insert_index in count + 1:
			var layout := _calculate_layout(&"group", group_id, insert_index)
			var distance: float = absf(drag_x - float(layout.placeholder_center_x))
			if distance < best_distance:
				best_distance = distance
				best_area = &"group"
				best_group_id = group_id
				best_index = insert_index

	var loose_count := _card_ids_without_drag(_loose_card_ids).size()
	for insert_index in loose_count + 1:
		var layout := _calculate_layout(&"loose", -1, insert_index)
		var distance: float = absf(drag_x - float(layout.placeholder_center_x))
		if distance < best_distance:
			best_distance = distance
			best_area = &"loose"
			best_group_id = -1
			best_index = insert_index

	var changed := (
		_preview_area != best_area
		or _preview_group_id != best_group_id
		or _preview_index != best_index
	)
	_preview_area = best_area
	_preview_group_id = best_group_id
	_preview_index = best_index
	return changed

func _relayout(animated: bool) -> void:
	if not is_node_ready() or size.x <= 0.0:
		return
	var layout := _calculate_layout(_preview_area, _preview_group_id, _preview_index)
	_last_layout = layout
	_sync_group_visuals(animated, layout)
	_sync_input_order(layout.entries)
	for card_id in layout.card_positions:
		if card_id == _dragging_card_id:
			continue
		var view: TongitsCardView = _card_views.get(card_id)
		if view == null:
			continue
		var target: Vector2 = layout.card_positions[card_id]
		view.z_index = int(layout.card_order.get(card_id, 0))
		var running_tween: Tween = _move_tweens.get(int(card_id))
		var previous_target: Vector2 = _move_targets.get(int(card_id), view.position)
		# 松手后的权威快照通常与拖拽预览拥有相同目标；继续原 Tween，避免缓动速度重置造成抖动。
		if (
			animated
			and running_tween != null
			and running_tween.is_valid()
			and running_tween.is_running()
			and previous_target.distance_to(target) <= 0.5
		):
			continue
		_stop_card_tween(int(card_id))
		if animated and view.position.distance_to(target) > 1.0:
			var tween := view.create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(view, "position", target, LAYOUT_ANIMATION_SECONDS)
			_move_tweens[int(card_id)] = tween
			_move_targets[int(card_id)] = target
			set_process(true)
		else:
			view.position = target
	_update_group_badges()
	queue_redraw()

func _relayout_collapse_expand() -> void:
	if not is_node_ready() or size.x <= 0.0:
		return
	var layout := _calculate_layout(&"", -1, -1)
	_last_layout = layout
	_sync_input_order(layout.entries)
	_set_card_interaction_enabled(false)
	var center_x := (size.x - CARD_SIZE.x) * 0.5
	_arrange_cards_remaining = layout.card_positions.size()

	# 牌组标识和牌面共用相同的两段时长：收拢阶段集中在中心，展开阶段同步变宽并淡入。
	for group_id in _group_visual_tweens.keys():
		_stop_group_visual_tween(int(group_id))
	_group_visuals.clear()
	for group: Dictionary in _groups:
		var group_id := int(group.group_id)
		var target := _group_rect_from_layout(group_id, layout)
		if target.size.x <= 0.0:
			continue
		var evaluation := TongitsMeldRules.evaluate(_cards_for_ids(group.card_ids))
		var state := GroupVisualState.new()
		state.rect = Rect2(center_x - 7.0, target.position.y, CARD_SIZE.x + 14.0, target.size.y)
		state.target_rect = target
		state.opacity = 0.0
		state.target_opacity = 1.0
		state.label = str(evaluation.label)
		state.group_type = int(evaluation.type) as TongitsMeldRules.GroupType
		state.color = _group_color(int(evaluation.type))
		_group_visuals[group_id] = state
		var badge_tween := create_tween()
		badge_tween.tween_interval(ARRANGE_COLLAPSE_SECONDS)
		badge_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		badge_tween.tween_property(state, "rect", target, ARRANGE_EXPAND_SECONDS)
		badge_tween.parallel().tween_property(state, "opacity", 1.0, ARRANGE_EXPAND_SECONDS)
		_group_visual_tweens[group_id] = badge_tween
		badge_tween.finished.connect(_on_group_visual_tween_finished.bind(group_id, badge_tween, false))

	for card_id in layout.card_positions:
		var view: TongitsCardView = _card_views.get(card_id)
		if view == null:
			_arrange_cards_remaining -= 1
			continue
		var target: Vector2 = layout.card_positions[card_id]
		_stop_card_tween(int(card_id))
		view.z_index = int(layout.card_order.get(card_id, 0))
		var tween := view.create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(view, "position", Vector2(center_x, view.position.y), ARRANGE_COLLAPSE_SECONDS)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(view, "position", target, ARRANGE_EXPAND_SECONDS)
		_move_tweens[int(card_id)] = tween
		_move_targets[int(card_id)] = target
		tween.finished.connect(_on_arrange_card_finished.bind(int(card_id), tween))
	if _arrange_cards_remaining <= 0:
		_finish_arrange_animation()
	else:
		set_process(true)
	_update_group_badges()
	queue_redraw()

func _on_arrange_card_finished(card_id: int, tween: Tween) -> void:
	if _move_tweens.get(card_id) != tween:
		return
	_move_tweens.erase(card_id)
	_move_targets.erase(card_id)
	_arrange_cards_remaining = maxi(0, _arrange_cards_remaining - 1)
	if _arrange_cards_remaining == 0:
		_finish_arrange_animation()

func _finish_arrange_animation() -> void:
	_set_card_interaction_enabled(true)
	_sync_input_order(_last_layout.entries)
	_update_group_badges()

func _relayout_deal() -> void:
	if not is_node_ready() or size.x <= 0.0:
		return
	# 发牌阶段只展示一整排散牌；权威快照中的牌组要等收拢后的展开阶段才表现出来。
	var layout := _calculate_deal_loose_layout()
	_last_layout = layout
	# 新一局不延续上一局的牌组标识，避免旧标识盖在牌堆或发牌路径上。
	for group_id in _group_visual_tweens.keys():
		_stop_group_visual_tween(int(group_id))
	_group_visuals.clear()
	_update_group_badges()
	_sync_input_order(layout.entries)
	var origin := _deal_origin_local()
	var deal_order := 0
	_deal_cards_remaining = layout.entries.size()
	_set_card_interaction_enabled(false)
	for entry: Dictionary in layout.entries:
		var card_id := int(entry.card_id)
		var view: TongitsCardView = _card_views.get(card_id)
		if view == null:
			_deal_cards_remaining -= 1
			continue
		var target: Vector2 = layout.card_positions[card_id]
		var target_z := int(layout.card_order.get(card_id, deal_order))
		_stop_card_tween(card_id)
		view.position = origin
		view.scale = Vector2.ONE * DEAL_START_SCALE
		view.show_back()
		# 牌堆阶段按发牌顺序设置临时层级，保证当前要发的牌始终位于最上方。
		view.z_index = layout.entries.size() - deal_order
		var tween := view.create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if deal_order > 0:
			tween.tween_interval(DEAL_CARD_STAGGER_SECONDS * deal_order)
		# 位移与缩放使用同一线性进度，避免位置提前贴近手牌、牌背却仍未完成放大的堆叠现象。
		tween.tween_property(view, "position", target, DEAL_CARD_ANIMATION_SECONDS).set_trans(Tween.TRANS_LINEAR)
		# 飞行阶段牌背保持正向，并从起点到落点持续线性放大，避免前半程尺寸变化不明显。
		tween.parallel().tween_property(view, "scale", Vector2.ONE, DEAL_CARD_ANIMATION_SECONDS).set_trans(Tween.TRANS_LINEAR)
		# 飞离牌堆后切换为最终手牌层级；切换发生在空中，不会在落位时闪动。
		tween.parallel().tween_callback(
			_set_deal_card_final_z.bind(card_id, tween, target_z)
		).set_delay(DEAL_Z_SWITCH_SECONDS)
		# 揭牌前锁定精确落点和 1.0 缩放，消除浮点插值或掉帧造成的末帧偏差。
		tween.tween_callback(_prepare_deal_card_reveal.bind(card_id, tween, target))
		# 落位后整张牌缩小，最小时切换牌面，再把牌面整体放大回 1；过程不旋转也不镜像。
		tween.tween_property(view, "scale", Vector2.ONE * DEAL_REVEAL_MIN_SCALE, DEAL_REVEAL_SHRINK_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(view.show_front)
		# 牌面出现后从 0.7 匀速放大到 1.0，并保留足够帧数让过渡清晰可见。
		tween.tween_property(view, "scale", Vector2.ONE, DEAL_FACE_GROW_SECONDS).set_trans(Tween.TRANS_LINEAR)
		_move_tweens[card_id] = tween
		_move_targets[card_id] = target
		tween.finished.connect(_on_deal_card_finished.bind(card_id, tween))
		deal_order += 1
	if _deal_cards_remaining <= 0:
		_set_card_interaction_enabled(true)
	else:
		set_process(true)
	queue_redraw()

func _calculate_deal_loose_layout() -> Dictionary:
	# 临时用“无牌组”的展示数据计算落点，不修改权威快照对应的真实牌组结构。
	var saved_groups := _groups
	var saved_loose := _loose_card_ids
	var all_card_ids: Array[int] = []
	for card_id in _cards.keys():
		all_card_ids.append(int(card_id))
	all_card_ids.sort_custom(_deal_card_id_before)
	_groups = []
	_loose_card_ids = all_card_ids
	var layout := _calculate_layout(&"", -1, -1)
	_groups = saved_groups
	_loose_card_ids = saved_loose
	return layout

func _deal_card_id_before(left_id: int, right_id: int) -> bool:
	var left: TongitsCard = _cards[left_id]
	var right: TongitsCard = _cards[right_id]
	var left_suit := int(TongitsHandServerSimulator.SUIT_PRIORITY[left.suit])
	var right_suit := int(TongitsHandServerSimulator.SUIT_PRIORITY[right.suit])
	if _sort_mode == TongitsHandServerSimulator.SortMode.SUIT_RANK:
		if left_suit != right_suit:
			return left_suit < right_suit
		return left.rank < right.rank
	if left.rank != right.rank:
		return left.rank < right.rank
	return left_suit < right_suit

func _deal_origin_local() -> Vector2:
	var origin_node := get_node_or_null(deal_origin_node_path) as Control
	if origin_node != null:
		var origin_global := origin_node.get_global_transform_with_canvas() * (origin_node.size * 0.5)
		return _global_to_local(origin_global) - CARD_SIZE * 0.5

	var viewport_size := get_viewport_rect().size
	var viewport_center := Vector2(
		viewport_size.x * deal_origin_viewport_ratio.x,
		viewport_size.y * deal_origin_viewport_ratio.y
	)
	return _global_to_local(viewport_center) - CARD_SIZE * 0.5

func _on_deal_card_finished(card_id: int, tween: Tween) -> void:
	if _move_tweens.get(card_id) != tween:
		return
	_move_tweens.erase(card_id)
	_move_targets.erase(card_id)
	_deal_cards_remaining = maxi(0, _deal_cards_remaining - 1)
	if _deal_cards_remaining == 0:
		# 发牌全部翻面后也用同一段收拢/展开动画整理为默认散牌顺序。
		_relayout_collapse_expand()

func _set_deal_card_final_z(card_id: int, tween: Tween, target_z: int) -> void:
	if _move_tweens.get(card_id) != tween:
		return
	var view: TongitsCardView = _card_views.get(card_id)
	if view != null:
		view.z_index = target_z

func _prepare_deal_card_reveal(card_id: int, tween: Tween, target: Vector2) -> void:
	if _move_tweens.get(card_id) != tween:
		return
	var view: TongitsCardView = _card_views.get(card_id)
	if view != null:
		view.position = target
		view.scale = Vector2.ONE

func _cancel_deal_animation_runtime() -> void:
	_deal_cards_remaining = 0
	_arrange_cards_remaining = 0
	# 普通快照可能中断发牌，必须恢复完整牌面，不能遗留半翻状态或牌背。
	for view: TongitsCardView in _card_views.values():
		view.scale = Vector2.ONE
		view.rotation = 0.0
		view.show_front()
	_set_card_interaction_enabled(true)

func _update_group_badges() -> void:
	if _group_badge_overlay == null:
		return
	var badges: Array[Dictionary] = []
	var ordered_group_ids: Array[int] = []
	for group: Dictionary in _groups:
		ordered_group_ids.append(int(group.group_id))
	# 已解散的牌组在退出 Tween 完成前仍保留标识，因此追加仍处于淡出的视觉状态。
	for existing_id in _group_visuals.keys():
		if not ordered_group_ids.has(int(existing_id)):
			ordered_group_ids.append(int(existing_id))
	for group_id in ordered_group_ids:
		var state: GroupVisualState = _group_visuals.get(group_id)
		if state == null:
			continue
		# 标识固定在正常手牌基线：牌组选中时卡牌可以上移，但标识保持原位。
		# 横坐标和宽度仍取自动画矩形，继续同步跟随牌组的横向布局变化。
		var card_bottom := _normal_card_y() + CARD_SIZE.y
		badges.append({
			"group_id": group_id,
			"rect": Rect2(
				state.rect.position.x,
				card_bottom - GROUP_BADGE_HEIGHT - GROUP_BADGE_BOTTOM_INSET,
				state.rect.size.x,
				GROUP_BADGE_HEIGHT
			),
			"label": state.label,
			"group_type": state.group_type,
			"opacity": state.opacity,
		})
	_group_badge_overlay.set_badges(badges)

func _sync_group_visuals(animated: bool, layout: Dictionary) -> void:
	var live_group_ids: Dictionary = {}
	for group: Dictionary in _groups:
		var group_id := int(group.group_id)
		live_group_ids[group_id] = true
		var target := _group_rect_from_layout(group_id, layout)
		if target.size.x <= 0.0:
			continue
		var evaluation := TongitsMeldRules.evaluate(_cards_for_ids(group.card_ids))
		var state: GroupVisualState = _group_visuals.get(group_id)
		if state == null:
			state = GroupVisualState.new()
			# 新牌组直接使用最终范围并淡入，避免不连续散牌形成超宽标识后再收缩。
			state.rect = target
			state.target_rect = target
			state.opacity = 0.0 if animated else 1.0
			state.target_opacity = state.opacity
			_group_visuals[group_id] = state
		state.label = str(evaluation.label)
		state.group_type = int(evaluation.type) as TongitsMeldRules.GroupType
		state.color = _group_color(int(evaluation.type))
		var running_tween: Tween = _group_visual_tweens.get(group_id)
		var same_target := (
			state.target_rect.position.distance_to(target.position)
			+ state.target_rect.size.distance_to(target.size)
		) <= 0.5 and absf(state.target_opacity - 1.0) <= 0.01
		# 预览目标被快照确认时保持原有速度曲线；标识由 state.rect 推导，也会同步连续运动。
		if (
			animated
			and same_target
			and running_tween != null
			and running_tween.is_valid()
			and running_tween.is_running()
		):
			continue
		_stop_group_visual_tween(group_id)
		var rect_distance := (
			state.rect.position.distance_to(target.position)
			+ state.rect.size.distance_to(target.size)
		)
		if animated and (rect_distance > 1.0 or absf(state.opacity - 1.0) > 0.01):
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(state, "rect", target, LAYOUT_ANIMATION_SECONDS)
			tween.parallel().tween_property(state, "opacity", 1.0, LAYOUT_ANIMATION_SECONDS)
			_group_visual_tweens[group_id] = tween
			state.target_rect = target
			state.target_opacity = 1.0
			tween.finished.connect(_on_group_visual_tween_finished.bind(group_id, tween, false))
			set_process(true)
		else:
			state.rect = target
			state.target_rect = target
			state.opacity = 1.0
			state.target_opacity = 1.0

	for existing_id in _group_visuals.keys():
		if live_group_ids.has(existing_id):
			continue
		var exiting_id := int(existing_id)
		var exiting_state: GroupVisualState = _group_visuals[exiting_id]
		var exiting_tween: Tween = _group_visual_tweens.get(exiting_id)
		if (
			exiting_state.target_opacity <= 0.01
			and exiting_tween != null
			and exiting_tween.is_valid()
			and exiting_tween.is_running()
		):
			continue
		_stop_group_visual_tween(exiting_id)
		if animated and exiting_state.opacity > 0.01:
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(exiting_state, "opacity", 0.0, LAYOUT_ANIMATION_SECONDS)
			exiting_state.target_opacity = 0.0
			_group_visual_tweens[exiting_id] = tween
			tween.finished.connect(_on_group_visual_tween_finished.bind(exiting_id, tween, true))
			set_process(true)
		else:
			_group_visuals.erase(exiting_id)

func _group_rect_from_layout(group_id: int, layout: Dictionary) -> Rect2:
	var visible_ids: Array = layout.group_cards.get(group_id, [])
	var xs: Array[float] = []
	var y := _normal_card_y()
	for card_id in visible_ids:
		if int(card_id) == PLACEHOLDER_ID:
			xs.append(float(layout.placeholder_center_x) - CARD_SIZE.x * 0.5)
		elif layout.card_positions.has(int(card_id)):
			xs.append(float(layout.card_positions[int(card_id)].x))
			y = float(layout.card_positions[int(card_id)].y)
	if xs.is_empty():
		return Rect2()
	var left: float = xs.min() - 7.0
	var right: float = xs.max() + CARD_SIZE.x + 7.0
	return Rect2(left, y - 8.0, right - left, CARD_SIZE.y + 10.0)

func _group_rect_from_current_cards(group: Dictionary, fallback: Rect2) -> Rect2:
	var xs: Array[float] = []
	var y := fallback.position.y + 8.0
	for card_id in group.card_ids:
		var view: TongitsCardView = _card_views.get(int(card_id))
		if view == null:
			continue
		xs.append(view.position.x)
		y = view.position.y
	if xs.is_empty():
		return fallback
	var left: float = xs.min() - 7.0
	var right: float = xs.max() + CARD_SIZE.x + 7.0
	return Rect2(left, y - 8.0, right - left, CARD_SIZE.y + 10.0)

func _stop_card_tween(card_id: int) -> void:
	var tween: Tween = _move_tweens.get(card_id)
	if tween != null and tween.is_valid():
		tween.kill()
	_move_tweens.erase(card_id)
	_move_targets.erase(card_id)

func _stop_group_visual_tween(group_id: int) -> void:
	var tween: Tween = _group_visual_tweens.get(group_id)
	if tween != null and tween.is_valid():
		tween.kill()
	_group_visual_tweens.erase(group_id)

func _on_group_visual_tween_finished(group_id: int, tween: Tween, remove_when_finished: bool) -> void:
	if _group_visual_tweens.get(group_id) != tween:
		return
	_group_visual_tweens.erase(group_id)
	if remove_when_finished and group_index(group_id) < 0:
		_group_visuals.erase(group_id)
	_update_group_badges()
	queue_redraw()

func _has_active_layout_tweens() -> bool:
	for tween: Tween in _move_tweens.values():
		if tween != null and tween.is_valid() and tween.is_running():
			return true
	for tween: Tween in _group_visual_tweens.values():
		if tween != null and tween.is_valid() and tween.is_running():
			return true
	return false

func _sync_input_order(entries: Array) -> void:
	# Control 的重叠区域按兄弟节点顺序命中；只设置 z_index 会出现
	# 右侧牌画在上面、点击却落到左侧牌的情况。这里让节点顺序与牌面顺序一致。
	var child_index := 0
	for entry in entries:
		var card_id := int(entry.card_id)
		if card_id == PLACEHOLDER_ID or card_id == _dragging_card_id:
			continue
		var view: TongitsCardView = _card_views.get(card_id)
		if view == null:
			continue
		move_child(view, child_index)
		child_index += 1
	# 拖拽牌必须同时位于绘制和输入顺序最上层。
	if _dragging_card_id >= 0:
		var dragged_view: TongitsCardView = _card_views.get(_dragging_card_id)
		if dragged_view != null:
			move_child(dragged_view, get_child_count() - 1)

func _calculate_layout(preview_area: StringName, preview_group_id: int, preview_index: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	var group_cards_for_draw: Dictionary = {}
	for group: Dictionary in _groups:
		var group_id := int(group.group_id)
		var ids := _card_ids_without_drag(group.card_ids)
		if preview_area == &"group" and preview_group_id == group_id and _dragging_card_id >= 0:
			ids.insert(clampi(preview_index, 0, ids.size()), PLACEHOLDER_ID)
		group_cards_for_draw[group_id] = ids
		_append_area_entries(entries, ids, &"group", group_id)

	var loose_ids := _card_ids_without_drag(_loose_card_ids)
	if preview_area == &"loose" and _dragging_card_id >= 0:
		loose_ids.insert(clampi(preview_index, 0, loose_ids.size()), PLACEHOLDER_ID)
	_append_area_entries(entries, loose_ids, &"loose", -1)

	var boundary_count := 0
	for index in range(1, entries.size()):
		if entries[index].area != entries[index - 1].area or entries[index].group_id != entries[index - 1].group_id:
			boundary_count += 1
	var available := maxf(1.0, size.x - HAND_MARGIN * 2.0)
	var card_step := MAX_CARD_STEP
	if entries.size() > 1:
		card_step = clampf(
			(available - CARD_SIZE.x - boundary_count * GROUP_GAP) / float(entries.size() - 1),
			MIN_CARD_STEP,
			MAX_CARD_STEP
		)
	var total_width := CARD_SIZE.x
	if entries.size() > 1:
		total_width += card_step * (entries.size() - 1) + boundary_count * GROUP_GAP
	var cursor_x := maxf(HAND_MARGIN, (size.x - total_width) * 0.5)
	var card_positions := {}
	var card_order := {}
	var placeholder_center_x := cursor_x + CARD_SIZE.x * 0.5
	var placeholder_entry_index := -1
	for entry_index in entries.size():
		if int(entries[entry_index].card_id) == PLACEHOLDER_ID:
			placeholder_entry_index = entry_index
			break
	var previous_area: StringName = &""
	var previous_group_id := -2
	for order_index in entries.size():
		var entry := entries[order_index]
		if order_index > 0 and (entry.area != previous_area or int(entry.group_id) != previous_group_id):
			cursor_x += GROUP_GAP
		var selected_offset := 0.0
		if entry.area == &"group" and int(entry.group_id) == _selected_group_id:
			selected_offset = SELECTED_OFFSET
		elif entry.area == &"loose" and _selected_loose_ids.has(int(entry.card_id)):
			selected_offset = SELECTED_OFFSET
		# 只抬起占位两侧紧邻的真实牌；拖出手牌范围后即恢复，且不改变任何逻辑顺序。
		if (
			_drag_is_over_hand
			and placeholder_entry_index >= 0
			and absi(order_index - placeholder_entry_index) == 1
			and int(entry.card_id) != PLACEHOLDER_ID
		):
			selected_offset += DRAG_NEIGHBOR_LIFT
		var card_position := Vector2(cursor_x, _normal_card_y() - selected_offset)
		if int(entry.card_id) == PLACEHOLDER_ID:
			placeholder_center_x = cursor_x + CARD_SIZE.x * 0.5
		else:
			card_positions[int(entry.card_id)] = card_position
			card_order[int(entry.card_id)] = order_index
		cursor_x += card_step
		previous_area = entry.area
		previous_group_id = int(entry.group_id)

	return {
		"card_positions": card_positions,
		"card_order": card_order,
		"placeholder_center_x": placeholder_center_x,
		"group_cards": group_cards_for_draw,
		"entries": entries,
		"card_step": card_step,
	}

func _append_area_entries(entries: Array[Dictionary], card_ids: Array, area: StringName, group_id: int) -> void:
	for card_id in card_ids:
		entries.append({"card_id": int(card_id), "area": area, "group_id": group_id})

func _draw() -> void:
	if _last_layout.is_empty():
		return
	if show_debug_outlines:
		for group: Dictionary in _groups:
			var group_id := int(group.group_id)
			var state: GroupVisualState = _group_visuals.get(group_id)
			if state == null:
				continue
			# 调试时恢复牌组类型色的范围底色和外框，正式显示默认保持关闭。
			draw_rect(state.rect, Color(state.color, 0.20 * state.opacity), true)
			draw_rect(state.rect, Color(state.color, state.opacity), false, 3.0)

	if show_debug_outlines and _dragging_card_id >= 0 and _drag_is_over_hand:
		# 拖拽占位框属于布局诊断信息，与牌组及选中描边共用调试开关。
		var placeholder_x := float(_last_layout.placeholder_center_x) - CARD_SIZE.x * 0.5
		draw_rect(Rect2(placeholder_x, _normal_card_y(), CARD_SIZE.x, CARD_SIZE.y), Color(0.75, 0.95, 1.0, 0.22), true)
		draw_rect(Rect2(placeholder_x, _normal_card_y(), CARD_SIZE.x, CARD_SIZE.y), Color("9eeeff"), false, 3.0)
	if show_debug_outlines:
		# 调试模式下显示实际发牌起点，便于按美术构图继续微调视口比例。
		draw_rect(Rect2(_deal_origin_local(), CARD_SIZE), Color("ff8a65"), false, 3.0)

func _group_color(group_type: int) -> Color:
	match group_type:
		TongitsMeldRules.GroupType.SPECIAL:
			return Color("ffd166")
		TongitsMeldRules.GroupType.VALID:
			return Color("62e6a7")
		_:
			return Color("ff718d")

func _normal_card_y() -> float:
	# 所有牌位都从 HandView 自身中心推导，调整场景中的框即可整体移动手牌。
	return roundf((size.y - CARD_SIZE.y) * 0.5 + hand_center_offset_y)

func _update_selected_views() -> void:
	for card_id in _card_views:
		var group_id := _group_for_card(int(card_id))
		# -1 同时表示“散牌”和“未选中任何组”，不能直接用相等判断。
		var group_selected := group_id >= 0 and group_id == _selected_group_id
		_card_views[card_id].selected = group_selected or _selected_loose_ids.has(int(card_id))

func _validate_selection() -> void:
	_selected_loose_ids = _selected_loose_ids.filter(func(card_id: int) -> bool: return _loose_card_ids.has(card_id))
	if group_index(_selected_group_id) < 0:
		_selected_group_id = -1
	_update_selected_views()
	selection_changed.emit(_selected_loose_ids.duplicate(), _selected_group_id)

func _group_for_card(card_id: int) -> int:
	for group: Dictionary in _groups:
		if group.card_ids.has(card_id):
			return int(group.group_id)
	return -1

func _location_for_card(card_id: int) -> Dictionary:
	for group: Dictionary in _groups:
		var index: int = Array(group.card_ids).find(card_id)
		if index >= 0:
			return {"area": &"group", "group_id": int(group.group_id), "index": index}
	return {"area": &"loose", "group_id": -1, "index": _loose_card_ids.find(card_id)}

func _card_ids_without_drag(source: Array) -> Array:
	var result := source.duplicate()
	if _dragging_card_id >= 0:
		result.erase(_dragging_card_id)
	return result

func _cards_for_ids(card_ids: Array) -> Array[TongitsCard]:
	var result: Array[TongitsCard] = []
	for card_id in card_ids:
		if _cards.has(card_id):
			result.append(_cards[card_id])
	return result

func _global_to_local(global_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_point
