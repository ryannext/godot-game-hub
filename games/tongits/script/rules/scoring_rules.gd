class_name TongitsScoringRules
extends RefCounted

# 计分入口集中在 rules 层，后续增加烧牌、Tongits、平局等结算时无需改 UI。
static func hand_points(hand: TongitsHand) -> int:
	return 0 if hand == null else hand.total_points()

static func lowest_hand_index(hands: Array[TongitsHand]) -> int:
	if hands.is_empty():
		return -1
	var winner_index := 0
	for index in range(1, hands.size()):
		if hand_points(hands[index]) < hand_points(hands[winner_index]):
			winner_index = index
	return winner_index
