class_name TongitsHandServerSimulator
extends RefCounted

# 这是开发期的本地权威边界。UI 只提交命令并接收快照，未来可原样替换为网络服务。
signal snapshot_changed(snapshot: Dictionary)
signal command_rejected(message: String)

enum SortMode {
	CUSTOM,
	SUIT_RANK,
	RANK_SUIT,
}

# 排序协议统一使用方块、梅花、红心、黑桃，不能依赖模型枚举的声明顺序。
const SUIT_PRIORITY := {
	TongitsCard.Suit.DIAMONDS: 0,
	TongitsCard.Suit.CLUBS: 1,
	TongitsCard.Suit.HEARTS: 2,
	TongitsCard.Suit.SPADES: 3,
}

var _cards: Dictionary = {}
var _groups: Array[Dictionary] = []
var _loose_card_ids: Array[int] = []
var _sort_mode := SortMode.RANK_SUIT
var _auto_arrange_enabled := true
var _revision := 0
var _next_group_id := 1
var _deck_remaining_count := 0

func reset_table() -> void:
	# 每次测试发牌前先提交一份空桌快照，确保旧手牌、牌组和剩余牌堆全部移除。
	_cards.clear()
	_groups.clear()
	_loose_card_ids.clear()
	_next_group_id = 1
	_deck_remaining_count = 0
	_sort_mode = SortMode.RANK_SUIT
	_auto_arrange_enabled = true
	_commit()

func start_deal(seed_value := 20260828) -> void:
	_cards.clear()
	_groups.clear()
	_loose_card_ids.clear()
	_next_group_id = 1
	_deck_remaining_count = 0
	_sort_mode = SortMode.RANK_SUIT
	_auto_arrange_enabled = true

	var deck := TongitsDeck.new()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	deck.reset_standard()
	deck.shuffle(random)
	for card_index in 13:
		var card := deck.draw()
		_cards[card.card_id] = card
		_loose_card_ids.append(card.card_id)
	# 单机三人局仍需为两名 AI 各发 12 张隐藏牌，桌面牌堆因此保留标准的 15 张。
	for _hidden_card_index in 24:
		deck.draw()
	_deck_remaining_count = deck.remaining()
	# 自动排列默认开启：发牌快照直接生成牌组与散牌，视图会在翻牌结束后统一收拢再展开。
	_auto_arrange_hand()
	_commit()

func request_auto_arrange(enabled: bool) -> void:
	if _auto_arrange_enabled == enabled:
		return
	_auto_arrange_enabled = enabled
	# 关闭时只冻结当前布局；重新开启时才收拢全部手牌并按规则重新自动组合。
	if _auto_arrange_enabled:
		_auto_arrange_hand()
	_commit()

func toggle_sort_mode() -> void:
	var next_mode := SortMode.SUIT_RANK if _sort_mode == SortMode.RANK_SUIT else SortMode.RANK_SUIT
	request_sort(next_mode)

func request_sort(mode: int) -> void:
	if mode != SortMode.SUIT_RANK and mode != SortMode.RANK_SUIT:
		_reject("未知的手牌排序方式")
		return
	# 外部命令使用 int 传输排序模式；完成白名单校验后显式恢复为枚举类型，避免类型警告。
	_sort_mode = mode as SortMode
	if _auto_arrange_enabled:
		_auto_arrange_hand()
	else:
		_sort_loose_cards()
		_sort_group_cards()
	_commit()

func create_group(card_ids: Array[int]) -> void:
	if card_ids.size() < 2:
		_reject("至少选择两张散牌才能成组")
		return
	var ordered_ids: Array[int] = []
	for loose_id in _loose_card_ids:
		if card_ids.has(loose_id):
			ordered_ids.append(loose_id)
	if ordered_ids.size() != card_ids.size():
		_reject("成组请求包含不属于散牌区的牌")
		return
	for card_id in ordered_ids:
		_loose_card_ids.erase(card_id)
	_groups.append({"group_id": _next_group_id, "card_ids": ordered_ids})
	_next_group_id += 1
	_sort_group_cards()
	_commit()

func dissolve_group(group_id: int) -> void:
	var group_index := _find_group_index(group_id)
	if group_index < 0:
		_reject("找不到要解散的牌组")
		return
	var dissolved_ids: Array[int] = _groups[group_index].card_ids.duplicate()
	_groups.remove_at(group_index)
	if _sort_mode == SortMode.CUSTOM:
		_loose_card_ids = dissolved_ids + _loose_card_ids
	else:
		_loose_card_ids.append_array(dissolved_ids)
		_sort_loose_cards()
	_commit()

func move_group(group_id: int, direction: int) -> void:
	var source_index := _find_group_index(group_id)
	var target_index := source_index + signi(direction)
	if source_index < 0 or target_index < 0 or target_index >= _groups.size():
		_reject("牌组已经位于该方向的边界")
		return
	var temporary := _groups[source_index]
	_groups[source_index] = _groups[target_index]
	_groups[target_index] = temporary
	_commit()

func move_card(card_id: int, target_area: StringName, target_group_id: int, target_index: int) -> void:
	if not _cards.has(card_id):
		_reject("手牌中不存在这张牌")
		return
	if target_area != &"group" and target_area != &"loose":
		_reject("未知的手牌投放区域")
		return
	if target_area == &"group" and _find_group_index(target_group_id) < 0:
		_reject("目标牌组不存在")
		return

	# 命令使用完整副本做事务回滚，任何目标异常都必须恢复原牌组、原顺序和排序模式。
	var previous_groups := _groups.duplicate(true)
	var previous_loose := _loose_card_ids.duplicate()
	var previous_sort_mode := _sort_mode
	var source_group_id := _find_group_for_card(card_id)
	var preserve_empty_group_id := target_group_id if target_area == &"group" and source_group_id == target_group_id else -1
	if not _remove_card_from_layout(card_id, preserve_empty_group_id):
		_reject("无法从原位置移除卡牌")
		return

	if target_area == &"group":
		var group_index := _find_group_index(target_group_id)
		if group_index < 0:
			_groups = previous_groups
			_loose_card_ids = previous_loose
			_sort_mode = previous_sort_mode
			_reject("目标牌组不存在")
			return
		var target_cards: Array = _groups[group_index].card_ids
		target_cards.insert(clampi(target_index, 0, target_cards.size()), card_id)
		_groups[group_index].card_ids = target_cards
	else:
		# 手动拖动只改变当前布局，不改变用户选择的点数/花色排序规则。
		_loose_card_ids.insert(clampi(target_index, 0, _loose_card_ids.size()), card_id)
	_commit()

func snapshot() -> Dictionary:
	var card_data: Array[Dictionary] = []
	for card_id in _cards:
		var card: TongitsCard = _cards[card_id]
		card_data.append({"card_id": card.card_id, "suit": card.suit, "rank": card.rank})
	return {
		"revision": _revision,
		"sort_mode": _sort_mode,
		"auto_arrange_enabled": _auto_arrange_enabled,
		"deck_remaining_count": _deck_remaining_count,
		"cards": card_data,
		"groups": _groups.duplicate(true),
		"loose_card_ids": _loose_card_ids.duplicate(),
	}

func _sort_loose_cards() -> void:
	if _sort_mode == SortMode.CUSTOM:
		return
	_loose_card_ids.sort_custom(_card_id_before)

func _sort_group_cards() -> void:
	# 排序规则是整副手牌的展示规则，因此已经成组的牌也必须同步切换内部顺序。
	if _sort_mode == SortMode.CUSTOM:
		return
	for group_index in _groups.size():
		var card_ids: Array = _groups[group_index].card_ids.duplicate()
		card_ids.sort_custom(_card_id_before)
		_groups[group_index].card_ids = card_ids

func _card_id_before(left_id: int, right_id: int) -> bool:
	var left: TongitsCard = _cards[left_id]
	var right: TongitsCard = _cards[right_id]
	if _sort_mode == SortMode.SUIT_RANK:
		if SUIT_PRIORITY[left.suit] != SUIT_PRIORITY[right.suit]:
			return SUIT_PRIORITY[left.suit] < SUIT_PRIORITY[right.suit]
		return left.rank < right.rank
	if left.rank != right.rank:
		return left.rank < right.rank
	return SUIT_PRIORITY[left.suit] < SUIT_PRIORITY[right.suit]

func _auto_arrange_hand() -> void:
	var all_card_ids: Array[int] = _loose_card_ids.duplicate()
	for group: Dictionary in _groups:
		for card_id in group.card_ids:
			all_card_ids.append(int(card_id))
	_groups.clear()

	var used_ids: Dictionary = {}
	for candidate: Dictionary in _build_auto_meld_candidates(all_card_ids):
		var overlaps := false
		for card_id in candidate.card_ids:
			if used_ids.has(int(card_id)):
				overlaps = true
				break
		if overlaps:
			continue
		var group_ids: Array[int] = []
		for card_id in candidate.card_ids:
			var typed_id := int(card_id)
			used_ids[typed_id] = true
			group_ids.append(typed_id)
		_groups.append({"group_id": _next_group_id, "card_ids": group_ids})
		_next_group_id += 1

	_loose_card_ids.clear()
	for card_id in all_card_ids:
		if not used_ids.has(card_id):
			_loose_card_ids.append(card_id)
	_sort_group_cards()
	_sort_loose_cards()

func _build_auto_meld_candidates(card_ids: Array[int]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	# 同点数组只生成最大组合；标准牌中每个点数最多四张。
	for rank in range(1, 14):
		var set_ids: Array[int] = []
		for card_id in card_ids:
			var card: TongitsCard = _cards[card_id]
			if card.rank == rank:
				set_ids.append(card_id)
		if set_ids.size() >= 3:
			set_ids.sort_custom(func(left_id: int, right_id: int) -> bool:
				return SUIT_PRIORITY[(_cards[left_id] as TongitsCard).suit] < SUIT_PRIORITY[(_cards[right_id] as TongitsCard).suit]
			)
			candidates.append({"kind": &"set", "card_ids": set_ids})

	# 为每段同花连续牌生成所有长度不少于三张的区间；发生冲突后仍可选中剩余的短顺子。
	for suit in SUIT_PRIORITY.keys():
		var suited_ids: Array[int] = []
		for card_id in card_ids:
			var card: TongitsCard = _cards[card_id]
			if card.suit == suit:
				suited_ids.append(card_id)
		suited_ids.sort_custom(func(left_id: int, right_id: int) -> bool:
			return (_cards[left_id] as TongitsCard).rank < (_cards[right_id] as TongitsCard).rank
		)
		var segment_start := 0
		while segment_start < suited_ids.size():
			var segment_end := segment_start + 1
			while segment_end < suited_ids.size():
				var previous: TongitsCard = _cards[suited_ids[segment_end - 1]]
				var current: TongitsCard = _cards[suited_ids[segment_end]]
				if current.rank != previous.rank + 1:
					break
				segment_end += 1
			for start_index in range(segment_start, segment_end):
				for end_index in range(start_index + 3, segment_end + 1):
					var run_ids: Array[int] = []
					for index in range(start_index, end_index):
						run_ids.append(suited_ids[index])
					candidates.append({"kind": &"run", "card_ids": run_ids})
			segment_start = segment_end

	# 先比较组合牌数；牌数相同优先三条/四条，再用首张牌稳定排序，避免布局跳动。
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_ids: Array = left.card_ids
		var right_ids: Array = right.card_ids
		if left_ids.size() != right_ids.size():
			return left_ids.size() > right_ids.size()
		if left.kind != right.kind:
			return left.kind == &"set"
		var left_card: TongitsCard = _cards[int(left_ids[0])]
		var right_card: TongitsCard = _cards[int(right_ids[0])]
		if left_card.rank != right_card.rank:
			return left_card.rank < right_card.rank
		return SUIT_PRIORITY[left_card.suit] < SUIT_PRIORITY[right_card.suit]
	)
	return candidates

func _remove_card_from_layout(card_id: int, preserve_empty_group_id := -1) -> bool:
	var loose_index := _loose_card_ids.find(card_id)
	if loose_index >= 0:
		_loose_card_ids.remove_at(loose_index)
		return true
	for group_index in _groups.size():
		var group_cards: Array = _groups[group_index].card_ids
		var card_index := group_cards.find(card_id)
		if card_index < 0:
			continue
		group_cards.remove_at(card_index)
		var group_id := int(_groups[group_index].group_id)
		if group_cards.is_empty() and group_id != preserve_empty_group_id:
			_groups.remove_at(group_index)
		else:
			_groups[group_index].card_ids = group_cards
		return true
	return false

func _find_group_for_card(card_id: int) -> int:
	for group: Dictionary in _groups:
		if group.card_ids.has(card_id):
			return int(group.group_id)
	return -1

func _find_group_index(group_id: int) -> int:
	for index in _groups.size():
		if int(_groups[index].group_id) == group_id:
			return index
	return -1

func _commit() -> void:
	_revision += 1
	snapshot_changed.emit(snapshot())

func _reject(message: String) -> void:
	command_rejected.emit(message)
