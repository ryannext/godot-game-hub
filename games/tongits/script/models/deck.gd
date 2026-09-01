class_name TongitsDeck
extends RefCounted

# 牌组仅管理标准牌的生成、洗牌和抽取，不包含回合或界面职责。
var _cards: Array[TongitsCard] = []

func reset_standard() -> void:
	_cards.clear()
	for suit in TongitsCard.Suit.values():
		for rank in range(1, 14):
			# ID 在一副牌内稳定且唯一，联网协议和 UI 都只传 ID，不传节点引用。
			var card_id: int = int(suit) * 13 + rank - 1
			_cards.append(TongitsCard.new(suit, rank, card_id))

func shuffle(random_source: RandomNumberGenerator = null) -> void:
	var random := random_source
	if random == null:
		random = RandomNumberGenerator.new()
		random.randomize()
	# 使用可注入的随机源，测试可固定 seed 得到可复现牌序。
	for index in range(_cards.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var temporary := _cards[index]
		_cards[index] = _cards[swap_index]
		_cards[swap_index] = temporary

func draw() -> TongitsCard:
	return null if _cards.is_empty() else _cards.pop_back()

func remaining() -> int:
	return _cards.size()

func snapshot() -> Array[TongitsCard]:
	# 返回副本，防止调用方绕过牌组 API 修改内部牌序。
	return _cards.duplicate()
