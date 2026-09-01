class_name TongitsGroupBadgeOverlay
extends Control

# 独立前景层确保类型标识绘制在卡牌之上，同时忽略鼠标，不影响点击和拖拽命中。
const DEFAULT_TEXT := Color("f3f5f7")
const VALID_BACKGROUND := preload("res://games/tongits/assets/ui/group_badges/card_type_valid.png")
const SPECIAL_BACKGROUND := preload("res://games/tongits/assets/ui/group_badges/card_type_special.png")
const INVALID_BACKGROUND := preload("res://games/tongits/assets/ui/group_badges/card_type_invalid.png")

var _badges: Array[Dictionary] = []

func set_badges(badges: Array[Dictionary]) -> void:
	_badges = badges
	queue_redraw()

func _draw() -> void:
	for badge: Dictionary in _badges:
		var rect: Rect2 = badge.rect
		var opacity := float(badge.get("opacity", 1.0))
		var group_type := int(badge.get("group_type", TongitsMeldRules.GroupType.INVALID))
		var background := _background_for_type(group_type)
		# 原版标识是 124×26 的横向底图；拉伸到牌组宽度后仍保留其圆角与渐变。
		draw_texture_rect(background, rect, false, Color(1.0, 1.0, 1.0, opacity))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(rect.position.x, rect.position.y + 19.0),
			str(badge.label),
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			14,
			_text_color(group_type, opacity)
		)

func _background_for_type(group_type: int) -> Texture2D:
	match group_type:
		TongitsMeldRules.GroupType.SPECIAL:
			return SPECIAL_BACKGROUND
		TongitsMeldRules.GroupType.VALID:
			return VALID_BACKGROUND
		_:
			return INVALID_BACKGROUND

func _text_color(group_type: int, opacity: float) -> Color:
	# 金色底图使用深色字确保对比度，绿色和红色底图继续使用浅色字。
	if group_type == TongitsMeldRules.GroupType.SPECIAL:
		return Color(Color("633b12"), opacity)
	return Color(DEFAULT_TEXT, opacity)
