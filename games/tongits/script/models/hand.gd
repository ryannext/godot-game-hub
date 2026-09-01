class_name TongitsHand
extends RefCounted

# 手牌保存玩家当前拥有的卡牌；组合拆分由 rules 层判断。
var cards: Array[TongitsCard] = []

func add_card(card: TongitsCard) -> void:
	if card != null:
		cards.append(card)

func remove_card(card: TongitsCard) -> bool:
	var index := cards.find(card)
	if index < 0:
		return false
	cards.remove_at(index)
	return true

func total_points() -> int:
	var result := 0
	for card in cards:
		result += card.point_value()
	return result

func size() -> int:
	return cards.size()
