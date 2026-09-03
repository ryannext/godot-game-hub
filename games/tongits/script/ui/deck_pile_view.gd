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

@onready var count_badge: Control = $DeckCountBadge
@onready var count_label: Label = $DeckCountBadge/DeckCountLabel
@onready var draw_pile_anchor: Control = $DrawPileAnchor
@onready var discard_pile_anchor: Control = $DiscardPileAnchor

var _card_count := 0
var _discard_card: TextureRect

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

func show_discard(card_data: Dictionary) -> void:
	clear_discard()
	var card := TongitsCard.new(
		int(card_data.get("suit", TongitsCard.Suit.CLUBS)),
		int(card_data.get("rank", 1)),
		int(card_data.get("card_id", -1))
	)
	_discard_card = TextureRect.new()
	_discard_card.name = "DiscardCard"
	_discard_card.position = discard_pile_anchor.position
	_discard_card.size = CARD_SIZE
	_discard_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discard_card.texture = TongitsCardArtLibrary.texture_for(card)
	_discard_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_discard_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_discard_card.material = _create_table_half_material(RIGHT_HALF_PIVOT_X)
	_discard_card.z_index = 1
	add_child(_discard_card)

func clear_discard() -> void:
	if not is_instance_valid(_discard_card):
		_discard_card = null
		return
	if _discard_card.get_parent() == self:
		remove_child(_discard_card)
	_discard_card.queue_free()
	_discard_card = null

func card_count() -> int:
	return _card_count

func _clear_card_layers() -> void:
	for child in get_children():
		if child is TextureRect and child.name.begins_with("PileCard"):
			remove_child(child)
			child.queue_free()
