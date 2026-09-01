class_name TongitsMeldRules
extends RefCounted

enum GroupType {
	VALID,
	SPECIAL,
	INVALID,
}

enum SpecialType {
	NONE,
	FOUR_ACES,
	LONG_RUN,
}

# 第一版组合规则支持同点数组和同花连续顺子；A 只作为低点牌处理。
static func is_valid_meld(cards: Array[TongitsCard]) -> bool:
	return is_set(cards) or is_run(cards)

static func evaluate(cards: Array[TongitsCard]) -> Dictionary:
	# 特殊牌型必须优先判断，否则四张 A 和四张顺子会先命中普通组合。
	if _is_four_aces(cards):
		return {
			"type": GroupType.SPECIAL,
			"special_type": SpecialType.FOUR_ACES,
			"label": "特殊·四张 A",
		}
	if cards.size() >= 4 and is_run(cards):
		return {
			"type": GroupType.SPECIAL,
			"special_type": SpecialType.LONG_RUN,
			"label": "特殊·%d 张顺子" % cards.size(),
		}
	if is_valid_meld(cards):
		return {
			"type": GroupType.VALID,
			"special_type": SpecialType.NONE,
			"label": "普通组合",
		}
	return {
		"type": GroupType.INVALID,
		"special_type": SpecialType.NONE,
		"label": "无效牌组",
	}

static func _is_four_aces(cards: Array[TongitsCard]) -> bool:
	if cards.size() != 4:
		return false
	for card in cards:
		if card.rank != 1:
			return false
	return true

static func is_set(cards: Array[TongitsCard]) -> bool:
	if cards.size() < 3 or cards.size() > 4:
		return false
	var expected_rank := cards[0].rank
	for card in cards:
		if card.rank != expected_rank:
			return false
	return true

static func is_run(cards: Array[TongitsCard]) -> bool:
	if cards.size() < 3:
		return false
	var expected_suit := cards[0].suit
	var sorted_cards: Array[TongitsCard] = cards.duplicate()
	sorted_cards.sort_custom(func(a: TongitsCard, b: TongitsCard) -> bool: return a.rank < b.rank)
	for index in sorted_cards.size():
		if sorted_cards[index].suit != expected_suit:
			return false
		if index > 0 and sorted_cards[index].rank != sorted_cards[index - 1].rank + 1:
			return false
	return true
