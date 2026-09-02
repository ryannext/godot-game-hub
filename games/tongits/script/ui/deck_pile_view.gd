class_name TongitsDeckPileView
extends Control

const CARD_BACK_TEXTURE := preload("res://games/tongits/res/images/tip/card_back.png")
const CARD_SIZE := Vector2(67.2, 90.0)
const TOP_CARD_POSITION := Vector2(7.4, 11.0)
const COUNT_BADGE_POSITION := Vector2(23.0, 39.0)
const LAYER_OFFSET_Y := 1.0
# 13 张起始牌堆以中心对称展开，固定底边为 +6px；后续牌堆共用这条底边。
const STACK_BOTTOM_OFFSET_Y := 6.0
const BOTTOM_TINT := Color(0.62, 0.62, 0.68, 1.0)

@onready var count_badge: Control = $DeckCountBadge
@onready var count_label: Label = $DeckCountBadge/DeckCountLabel

var _card_count := 0

func _ready() -> void:
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
		card_back.position = TOP_CARD_POSITION + Vector2(0.0, top_offset_y + LAYER_OFFSET_Y * depth)
		card_back.size = CARD_SIZE
		card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 牌背保持与 HandView 同层；按“底层先创建、顶层后创建”的兄弟顺序完成覆盖。
		card_back.z_index = 0
		card_back.modulate = _layer_tint(depth)
		add_child(card_back)
	count_badge.position = COUNT_BADGE_POSITION + Vector2(0.0, top_offset_y)
	count_label.text = str(_card_count)
	count_badge.visible = show_count and _card_count > 0
	count_badge.z_index = _card_count + 1

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
