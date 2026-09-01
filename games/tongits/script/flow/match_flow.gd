class_name TongitsMatchFlow
extends RefCounted

# 流程对象协调牌组和手牌，但不访问场景节点，便于未来单元测试和 AI 模拟。
enum Phase {
	SETUP,
	DRAW,
	DISCARD,
	FINISHED,
}

var phase := Phase.SETUP
var deck := TongitsDeck.new()
var hands: Array[TongitsHand] = []
var discard_pile: Array[TongitsCard] = []
var current_player := 0

func start_match(player_count := 3, random_source: RandomNumberGenerator = null) -> bool:
	if player_count < 2 or player_count > 3:
		return false
	hands.clear()
	discard_pile.clear()
	for player_index in player_count:
		hands.append(TongitsHand.new())
	deck.reset_standard()
	deck.shuffle(random_source)

	# 发牌者（索引 0）拿 13 张，其余玩家 12 张，并从弃牌阶段开始。
	for round_index in 13:
		for player_index in player_count:
			if round_index == 12 and player_index != 0:
				continue
			hands[player_index].add_card(deck.draw())
	current_player = 0
	phase = Phase.DISCARD
	return true

func draw_from_stock() -> TongitsCard:
	if phase != Phase.DRAW or deck.remaining() == 0:
		return null
	var card := deck.draw()
	hands[current_player].add_card(card)
	phase = Phase.DISCARD
	return card

func discard(card: TongitsCard) -> bool:
	if phase != Phase.DISCARD or not hands[current_player].remove_card(card):
		return false
	discard_pile.append(card)
	current_player = (current_player + 1) % hands.size()
	phase = Phase.DRAW
	return true
