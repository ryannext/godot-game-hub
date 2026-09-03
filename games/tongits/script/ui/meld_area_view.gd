@tool
class_name TongitsMeldAreaView
extends Control

enum FlowDirection {
	LEFT_TO_RIGHT,
	RIGHT_TO_LEFT,
}

const CARD_VIEW_SCRIPT := preload("res://games/tongits/script/ui/card_view.gd")

@export_category("牌组排列")
@export var flow_direction := FlowDirection.LEFT_TO_RIGHT
@export var wrap_melds := true
@export var center_rows_vertically := false
@export var card_size := Vector2(32.0, 43.0)
@export_range(4.0, 64.0, 0.5) var card_step := 21.0
@export_range(0.0, 48.0, 0.5) var meld_gap := 14.0
@export_range(0.0, 48.0, 0.5) var row_gap := 8.0
@export_range(0.0, 48.0, 0.5) var horizontal_padding := 32.0
@export_range(0.0, 48.0, 0.5) var vertical_padding := 12.0

@export_category("桌面透视")
@export_range(-45.0, 45.0, 0.5) var perspective_rotation_x := 10.0
@export_range(1.0, 179.0, 1.0) var perspective_fov := 75.0

var _card_views: Array[TongitsCardView] = []
var _view_slots: Array[Dictionary] = []

func _ready() -> void:
	clip_contents = false
	resized.connect(_relayout)
	_relayout()

# 接受与手牌服务器相同的快照结构：cards + groups。
func apply_snapshot(snapshot: Dictionary) -> void:
	set_melds(snapshot.get("groups", []), snapshot.get("cards", []))

func set_melds(melds: Array, card_data_list: Array) -> void:
	clear_melds()
	var cards_by_id := {}
	for card_data: Dictionary in card_data_list:
		var card := TongitsCard.new(
			int(card_data.get("suit", TongitsCard.Suit.CLUBS)),
			int(card_data.get("rank", 1)),
			int(card_data.get("card_id", -1))
		)
		cards_by_id[card.card_id] = card

	for meld_index in melds.size():
		var meld: Dictionary = melds[meld_index]
		var card_ids: Array = meld.get("card_ids", [])
		for card_index in card_ids.size():
			var card_id := int(card_ids[card_index])
			if not cards_by_id.has(card_id):
				continue
			var view := CARD_VIEW_SCRIPT.new() as TongitsCardView
			view.name = "Meld%dCard%d" % [meld_index, card_index]
			view.setup(cards_by_id[card_id])
			view.set_display_size(card_size)
			view.set_perspective(perspective_rotation_x, perspective_fov)
			view.mouse_filter = Control.MOUSE_FILTER_IGNORE
			view.z_index = card_index
			add_child(view)
			_card_views.append(view)
			_view_slots.append({
				"view": view,
				"meld_index": meld_index,
				"card_index": card_index,
			})
	_relayout()

func clear_melds() -> void:
	for view: TongitsCardView in _card_views:
		if is_instance_valid(view):
			if view.get_parent() == self:
				remove_child(view)
			view.queue_free()
	_card_views.clear()
	_view_slots.clear()

func calculate_layout(meld_sizes: Array[int]) -> Array:
	var positions: Array = []
	for meld_size in meld_sizes:
		positions.append([])
	if meld_sizes.is_empty():
		return positions
	_layout_wrapped_rows(meld_sizes, positions)
	return positions

func _layout_wrapped_rows(meld_sizes: Array[int], positions: Array) -> void:
	var usable_width := maxf(0.0, size.x - horizontal_padding * 2.0)
	var visual_card_size := _projected_card_extent()
	var visual_overhang := (visual_card_size - card_size) * 0.5
	var rows: Array[Array] = []
	var current_row: Array[Dictionary] = []
	var current_width := 0.0
	for meld_index in meld_sizes.size():
		var count := maxi(0, meld_sizes[meld_index])
		if count == 0:
			continue
		var step := _fit_card_step(count, usable_width)
		var meld_width := visual_card_size.x + step * maxi(0, count - 1)
		var required_width := meld_width if current_row.is_empty() else meld_gap + meld_width
		if wrap_melds and not current_row.is_empty() and current_width + required_width > usable_width:
			rows.append(current_row)
			current_row = []
			current_width = 0.0
		current_row.append({
			"meld_index": meld_index,
			"card_count": count,
			"step": step,
			"width": meld_width,
		})
		current_width += meld_width if current_width == 0.0 else meld_gap + meld_width
	if not current_row.is_empty():
		rows.append(current_row)
	if rows.is_empty():
		return

	var usable_height := maxf(0.0, size.y - vertical_padding * 2.0 - visual_card_size.y)
	var row_step := 0.0
	if rows.size() > 1:
		row_step = minf(visual_card_size.y + row_gap, usable_height / float(rows.size() - 1))
	var block_height := visual_card_size.y + row_step * maxi(0, rows.size() - 1)
	var first_y := vertical_padding
	if center_rows_vertically:
		first_y = maxf(vertical_padding, (size.y - block_height) * 0.5)

	for row_index in rows.size():
		var cursor_x := horizontal_padding
		if flow_direction == FlowDirection.RIGHT_TO_LEFT:
			cursor_x = size.x - horizontal_padding
		for entry: Dictionary in rows[row_index]:
			var meld_index := int(entry.meld_index)
			var count := int(entry.card_count)
			var step := float(entry.step)
			for card_index in count:
				var x := cursor_x + visual_overhang.x + step * card_index
				if flow_direction == FlowDirection.RIGHT_TO_LEFT:
					x = cursor_x - card_size.x - visual_overhang.x - step * card_index
				positions[meld_index].append(Vector2(x, first_y + visual_overhang.y + row_step * row_index))
			if flow_direction == FlowDirection.LEFT_TO_RIGHT:
				cursor_x += float(entry.width) + meld_gap
			else:
				cursor_x -= float(entry.width) + meld_gap

func _fit_card_step(card_count: int, available_width: float) -> float:
	if card_count <= 1:
		return 0.0
	return minf(card_step, maxf(0.0, (available_width - _projected_card_extent().x) / float(card_count - 1)))

func _projected_card_extent() -> Vector2:
	# Meld 卡牌通过缩放完整原生 Shader 画布得到目标尺寸，外部布局直接使用目标显示尺寸。
	return card_size

func _relayout() -> void:
	if _view_slots.is_empty():
		return
	var meld_sizes: Array[int] = []
	for slot: Dictionary in _view_slots:
		var meld_index := int(slot.meld_index)
		while meld_sizes.size() <= meld_index:
			meld_sizes.append(0)
		meld_sizes[meld_index] += 1
	var positions := calculate_layout(meld_sizes)
	for slot: Dictionary in _view_slots:
		var view := slot.view as TongitsCardView
		var meld_index := int(slot.meld_index)
		var card_index := int(slot.card_index)
		if is_instance_valid(view) and meld_index < positions.size() and card_index < positions[meld_index].size():
			view.position = positions[meld_index][card_index]
