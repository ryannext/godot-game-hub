class_name TongitsDeckPileView
extends Control

signal draw_requested

const CARD_BACK_TEXTURE := preload("res://games/tongits/res/images/tip/card_back.png")
const TABLE_SPLIT_CARD_SHADER := preload("res://games/tongits/assets/shaders/table_split_card.gdshader")
const CARD_SIZE := Vector2(67.2, 90.0)
const COUNT_BADGE_OFFSET := Vector2(15.6, 28.0)
const LAYER_OFFSET_Y := 1.0
const LEFT_HALF_PIVOT_X := 1.0
const RIGHT_HALF_PIVOT_X := 0.0
const TABLE_FAR_SCALE := 0.94
const TABLE_NEAR_SCALE := 1.06

@onready var count_badge: Control = $DeckCountBadge
@onready var count_label: Label = $DeckCountBadge/DeckCountLabel
@onready var draw_pile_anchor: Control = $DrawPileAnchor
@onready var discard_pile_anchor: Control = $DiscardPileAnchor

var _card_count := 0
var _draw_enabled := false
var _discard_cards: Array[TextureRect] = []
var _discard_card_ids: Array[int] = []

func _ready() -> void:
	# 运行时按真实剩余数量生成牌背；场景文件不再保存固定的三层示意节点。
	set_card_count(0, false)
	clear_discard()

func set_card_count(card_count: int, show_count: bool) -> void:
	_card_count = maxi(0, card_count)
	_clear_card_layers()
	# 每次牌数变化都以锚点 Y=0 重新居中：奇数张包含 0，偶数张跨在 ±0.5px 两侧。
	var top_offset_y := 0.0
	if _card_count > 0:
		top_offset_y = -LAYER_OFFSET_Y * float(_card_count - 1) * 0.5
	# 先创建最底层、最后创建顶层，利用兄弟绘制顺序让顶牌盖住下层牌。
	for depth in range(_card_count - 1, -1, -1):
		var card_back := TextureRect.new()
		card_back.name = "PileCard%02d" % depth
		card_back.position = draw_pile_anchor.position + Vector2(0.0, top_offset_y + LAYER_OFFSET_Y * depth)
		card_back.size = CARD_SIZE
		card_back.mouse_filter = Control.MOUSE_FILTER_STOP if depth == 0 and _draw_enabled else Control.MOUSE_FILTER_IGNORE
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 每张牌都保留完整牌背并独立完成透视，然后再按 Y 轴顺序叠加。
		card_back.material = _create_table_half_material(LEFT_HALF_PIVOT_X)
		# 牌背保持与 HandView 同层；按“底层先创建、顶层后创建”的兄弟顺序完成覆盖。
		card_back.z_index = 0
		add_child(card_back)
		if depth == 0:
			card_back.gui_input.connect(_on_draw_pile_gui_input)
	count_badge.position = draw_pile_anchor.position + COUNT_BADGE_OFFSET + Vector2(0.0, top_offset_y)
	count_label.text = str(_card_count)
	count_badge.visible = show_count and _card_count > 0
	count_badge.z_index = _card_count + 1

func set_draw_enabled(enabled: bool) -> void:
	_draw_enabled = enabled and _card_count > 0
	var top_card := get_node_or_null("PileCard00") as TextureRect
	if top_card != null:
		top_card.mouse_filter = Control.MOUSE_FILTER_STOP if _draw_enabled else Control.MOUSE_FILTER_IGNORE

func _on_draw_pile_gui_input(event: InputEvent) -> void:
	if not _draw_enabled:
		return
	var released: bool = (
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
		or (event is InputEventScreenTouch and not event.pressed)
	)
	if not released:
		return
	_draw_enabled = false
	draw_requested.emit()
	accept_event()

func _create_table_half_material(pivot_x: float) -> ShaderMaterial:
	var perspective_material := ShaderMaterial.new()
	perspective_material.shader = TABLE_SPLIT_CARD_SHADER
	perspective_material.set_shader_parameter(&"item_size_px", CARD_SIZE)
	perspective_material.set_shader_parameter(&"pivot_x", pivot_x)
	perspective_material.set_shader_parameter(&"far_scale", TABLE_FAR_SCALE)
	perspective_material.set_shader_parameter(&"near_scale", TABLE_NEAR_SCALE)
	return perspective_material

func set_discard_cards(card_data_list: Array) -> void:
	var first_visible_index := maxi(0, card_data_list.size() - 1)
	var visible_cards := card_data_list.slice(first_visible_index)
	var visible_ids: Array[int] = []
	for card_data: Dictionary in visible_cards:
		visible_ids.append(int(card_data.get("card_id", -1)))
	if visible_ids == _discard_card_ids:
		return

	for discard_card in _discard_cards:
		_free_discard_card(discard_card)
	_discard_cards.clear()
	if not visible_cards.is_empty():
		var discard_card := _create_discard_card(visible_cards[0])
		discard_card.name = "DiscardCardTop"
		discard_card.z_index = 1
		discard_card.rotation = 0.0
		discard_card.modulate = Color.WHITE
		_discard_cards.append(discard_card)
	_discard_card_ids = visible_ids

func clear_discard() -> void:
	for discard_card in _discard_cards:
		_free_discard_card(discard_card)
	_discard_cards.clear()
	_discard_card_ids.clear()

func _create_discard_card(card_data: Dictionary) -> TextureRect:
	var card := TongitsCard.new(
		int(card_data.get("suit", TongitsCard.Suit.CLUBS)),
		int(card_data.get("rank", 1)),
		int(card_data.get("card_id", -1))
	)
	var discard_card := TextureRect.new()
	discard_card.position = discard_pile_anchor.position
	discard_card.size = CARD_SIZE
	discard_card.pivot_offset = CARD_SIZE * 0.5
	discard_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	discard_card.texture = TongitsCardArtLibrary.texture_for(card)
	discard_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	discard_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	discard_card.material = _create_table_half_material(RIGHT_HALF_PIVOT_X)
	discard_card.set_meta(&"card_id", card.card_id)
	add_child(discard_card)
	return discard_card

func _free_discard_card(discard_card: TextureRect) -> void:
	if not is_instance_valid(discard_card):
		return
	if discard_card.get_parent() == self:
		remove_child(discard_card)
	discard_card.queue_free()

func card_count() -> int:
	return _card_count

func _clear_card_layers() -> void:
	for child in get_children():
		if child is TextureRect and child.name.begins_with("PileCard"):
			remove_child(child)
			child.queue_free()
