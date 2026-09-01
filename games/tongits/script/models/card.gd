class_name TongitsCard
extends RefCounted

# 卡牌是纯数据对象，不继承 Node，规则测试无需创建场景树。
enum Suit {
	CLUBS,
	DIAMONDS,
	HEARTS,
	SPADES,
}

var suit: int
var rank: int
var card_id: int

func _init(card_suit := Suit.CLUBS, card_rank := 1, unique_id := -1) -> void:
	suit = card_suit
	rank = clampi(card_rank, 1, 13)
	card_id = unique_id

func point_value() -> int:
	# Tongits 计分中 A 计 1 分，J/Q/K 均计 10 分。
	return mini(rank, 10)

func display_name() -> String:
	var rank_names := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
	var suit_names := ["♣", "♦", "♥", "♠"]
	return "%s%s" % [rank_names[rank - 1], suit_names[suit]]
