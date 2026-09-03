class_name TongitsDeckPileView
extends Control

const CARD_BACK_TEXTURE := preload("res://games/tongits/res/images/tip/card_back.png")
const TABLE_SPLIT_CARD_SHADER := preload("res://games/tongits/assets/shaders/table_split_card.gdshader")
const CARD_SIZE := Vector2(67.2, 90.0)
const COUNT_BADGE_OFFSET := Vector2(15.6, 28.0)
const LAYER_OFFSET_Y := 1.4
const LEFT_HALF_PIVOT_X := 1.0
const RIGHT_HALF_PIVOT_X := 0.0
const TABLE_FAR_SCALE := 0.94
const TABLE_NEAR_SCALE := 1.06
const DISCARD_SLOT_OFFSET_X := 10.0
const DISCARD_TRANSITION_SECONDS := 0.22

@onready var count_badge: Control = $DeckCountBadge
@onready var count_label: Label = $DeckCountBadge/DeckCountLabel
@onready var draw_pile_anchor: Control = $DrawPileAnchor
@onready var discard_pile_anchor: Control = $DiscardPileAnchor

var _card_count := 0
var _discard_cards: Array[TextureRect] = []
var _discard_card_ids: Array[int] = []
var _discard_exiting_cards: Array[TextureRect] = []
var _discard_transition_tween: Tween

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
		card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 每张牌都保留完整牌背并独立完成透视，然后再按 Y 轴顺序叠加。
		card_back.material = _create_table_half_material(LEFT_HALF_PIVOT_X)
		# 牌背保持与 HandView 同层；按“底层先创建、顶层后创建”的兄弟顺序完成覆盖。
		card_back.z_index = 0
		add_child(card_back)
	count_badge.position = draw_pile_anchor.position + COUNT_BADGE_OFFSET + Vector2(0.0, top_offset_y)
	count_label.text = str(_card_count)
	count_badge.visible = show_count and _card_count > 0
	count_badge.z_index = _card_count + 1

func _create_table_half_material(pivot_x: float) -> ShaderMaterial:
	var perspective_material := ShaderMaterial.new()
	perspective_material.shader = TABLE_SPLIT_CARD_SHADER
	perspective_material.set_shader_parameter(&"item_size_px", CARD_SIZE)
	perspective_material.set_shader_parameter(&"pivot_x", pivot_x)
	perspective_material.set_shader_parameter(&"far_scale", TABLE_FAR_SCALE)
	perspective_material.set_shader_parameter(&"near_scale", TABLE_NEAR_SCALE)
	return perspective_material

func set_discard_cards(card_data_list: Array) -> void:
	var first_visible_index := maxi(0, card_data_list.size() - 2)
	var visible_cards := card_data_list.slice(first_visible_index)
	var visible_ids: Array[int] = []
	for card_data: Dictionary in visible_cards:
		visible_ids.append(int(card_data.get("card_id", -1)))
	if visible_ids == _discard_card_ids:
		return

	_stop_discard_transition()
	var existing_by_id := {}
	for discard_card in _discard_cards:
		existing_by_id[int(discard_card.get_meta(&"card_id", -1))] = discard_card
		discard_card.name = "DiscardCardTransition"

	var next_cards: Array[TextureRect] = []
	for visible_index in visible_cards.size():
		var card_data: Dictionary = visible_cards[visible_index]
		var card_id := int(card_data.get("card_id", -1))
		var discard_card: TextureRect = existing_by_id.get(card_id)
		var is_new_card := discard_card == null
		if is_new_card:
			discard_card = _create_discard_card(card_data)
		discard_card.name = "DiscardCardTop" if visible_index == visible_cards.size() - 1 else "DiscardCardOld"
		discard_card.z_index = visible_index + 1
		discard_card.rotation = 0.0
		var target_position := _discard_slot_position(visible_index, visible_cards.size())
		if _discard_card_ids.is_empty():
			discard_card.position = target_position
			discard_card.modulate = Color.WHITE
		else:
			_ensure_discard_transition_tween()
			if is_new_card:
				discard_card.position = target_position
				discard_card.modulate = Color(1.0, 1.0, 1.0, 0.0)
				_discard_transition_tween.tween_property(discard_card, "modulate:a", 1.0, DISCARD_TRANSITION_SECONDS)
			else:
				_discard_transition_tween.tween_property(discard_card, "position", target_position, DISCARD_TRANSITION_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		next_cards.append(discard_card)

	for old_card in _discard_cards:
		var old_card_id := int(old_card.get_meta(&"card_id", -1))
		if visible_ids.has(old_card_id):
			continue
		old_card.name = "DiscardCardExiting"
		old_card.z_index = 0
		_discard_exiting_cards.append(old_card)
		_ensure_discard_transition_tween()
		_discard_transition_tween.tween_property(old_card, "modulate:a", 0.0, DISCARD_TRANSITION_SECONDS)

	_discard_cards = next_cards
	_discard_card_ids = visible_ids
	if _discard_transition_tween != null:
		_discard_transition_tween.finished.connect(_finish_discard_transition)

func clear_discard() -> void:
	_stop_discard_transition()
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

func _discard_slot_position(visible_index: int, visible_count: int) -> Vector2:
	if visible_count < 2:
		return discard_pile_anchor.position
	var offset_x := -DISCARD_SLOT_OFFSET_X if visible_index == 0 else DISCARD_SLOT_OFFSET_X
	return discard_pile_anchor.position + Vector2(offset_x, 0.0)

func _ensure_discard_transition_tween() -> void:
	if _discard_transition_tween == null:
		_discard_transition_tween = create_tween().set_parallel(true)

func _stop_discard_transition() -> void:
	if _discard_transition_tween != null and _discard_transition_tween.is_valid():
		_discard_transition_tween.kill()
	_discard_transition_tween = null
	for discard_card in _discard_exiting_cards:
		_free_discard_card(discard_card)
	_discard_exiting_cards.clear()

func _finish_discard_transition() -> void:
	_discard_transition_tween = null
	for discard_card in _discard_exiting_cards:
		_free_discard_card(discard_card)
	_discard_exiting_cards.clear()

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
