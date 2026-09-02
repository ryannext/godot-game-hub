@tool
extends McpTestSuite

# 手牌交互的回归测试聚焦容易在动画与输入重构时重新出现的边界条件。
func suite_name() -> String:
	return "tongits_interactions"

func test_mouse_release_without_press_does_not_tap() -> void:
	var view := track(TongitsCardView.new()) as TongitsCardView
	var tapped := false
	view.tapped.connect(func(_card_id: int) -> void: tapped = true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	view._gui_input(release)
	assert_false(tapped, "孤立的鼠标 release 不应触发卡牌点击")

func test_same_single_card_group_drop_keeps_group() -> void:
	var simulator := TongitsHandServerSimulator.new()
	simulator.start_deal(12345)
	simulator.request_auto_arrange(false)
	var state := simulator.snapshot()
	var ids: Array[int] = [int(state.loose_card_ids[0]), int(state.loose_card_ids[1])]
	simulator.create_group(ids)
	state = simulator.snapshot()
	var group_id := int(state.groups[-1].group_id)
	var group_count_before: int = state.groups.size()
	simulator.move_card(ids[0], &"loose", -1, 0)
	simulator.move_card(ids[1], &"group", group_id, 0)
	state = simulator.snapshot()
	assert_eq(state.groups.size(), group_count_before, "拖回只剩一张牌的原组时不应删除牌组")
	var restored_group: Dictionary = state.groups.filter(func(group: Dictionary) -> bool: return int(group.group_id) == group_id)[0]
	assert_eq(int(restored_group.card_ids[0]), ids[1], "原组应保留被拖动的卡牌")

func test_default_mode_is_rank_first_with_auto_arrange_enabled() -> void:
	var simulator := TongitsHandServerSimulator.new()
	simulator.start_deal(20260829)
	var state := simulator.snapshot()
	assert_true(bool(state.auto_arrange_enabled), "新局默认应开启自动排列")
	assert_eq(int(state.sort_mode), TongitsHandServerSimulator.SortMode.RANK_SUIT, "新局默认应为点数优先")
	assert_eq(int(state.deck_remaining_count), 15, "三人局发完牌后牌堆应剩余 15 张")

func test_reset_table_clears_cards_groups_and_deck() -> void:
	var simulator := TongitsHandServerSimulator.new()
	simulator.start_deal(20260829)
	simulator.reset_table()
	var state := simulator.snapshot()
	assert_true(state.cards.is_empty(), "初始化桌面后不应保留手牌")
	assert_true(state.groups.is_empty(), "初始化桌面后不应保留牌组")
	assert_true(state.loose_card_ids.is_empty(), "初始化桌面后不应保留散牌")
	assert_eq(int(state.deck_remaining_count), 0, "初始化桌面后不应显示剩余牌堆")
	assert_true(bool(state.auto_arrange_enabled), "初始化桌面后应恢复默认自动排列")
	assert_eq(int(state.sort_mode), TongitsHandServerSimulator.SortMode.RANK_SUIT, "初始化桌面后应恢复点数优先")

func test_disabling_auto_arrange_preserves_current_layout() -> void:
	var simulator := TongitsHandServerSimulator.new()
	simulator.start_deal(20260829)
	var before := simulator.snapshot()
	simulator.request_auto_arrange(false)
	var after := simulator.snapshot()
	assert_false(bool(after.auto_arrange_enabled), "关闭后按钮状态应写入快照")
	assert_eq(after.groups, before.groups, "关闭自动排列不应拆除现有牌组")
	assert_eq(after.loose_card_ids, before.loose_card_ids, "关闭自动排列不应改变散牌顺序")

func test_auto_arrange_prioritizes_four_of_a_kind_and_uses_new_suit_order() -> void:
	var simulator := TongitsHandServerSimulator.new()
	_configure_cards(simulator, [
		TongitsCard.new(TongitsCard.Suit.SPADES, 7, 0),
		TongitsCard.new(TongitsCard.Suit.HEARTS, 7, 1),
		TongitsCard.new(TongitsCard.Suit.CLUBS, 7, 2),
		TongitsCard.new(TongitsCard.Suit.DIAMONDS, 7, 3),
		TongitsCard.new(TongitsCard.Suit.CLUBS, 2, 4),
		TongitsCard.new(TongitsCard.Suit.DIAMONDS, 1, 5),
	])
	simulator._auto_arrange_hand()
	var state := simulator.snapshot()
	assert_eq(state.groups.size(), 1, "四张同点牌应自动形成一个四条")
	assert_eq(state.groups[0].card_ids, [3, 2, 1, 0], "四条内部应按方块、梅花、红心、黑桃排列")
	assert_eq(state.loose_card_ids, [5, 4], "剩余散牌默认应按点数从 A 开始排列")

func test_sort_modes_follow_diamond_club_heart_spade_priority() -> void:
	var simulator := TongitsHandServerSimulator.new()
	_configure_cards(simulator, [
		TongitsCard.new(TongitsCard.Suit.HEARTS, 5, 0),
		TongitsCard.new(TongitsCard.Suit.SPADES, 3, 1),
		TongitsCard.new(TongitsCard.Suit.DIAMONDS, 5, 2),
		TongitsCard.new(TongitsCard.Suit.CLUBS, 3, 3),
	])
	simulator.request_sort(TongitsHandServerSimulator.SortMode.RANK_SUIT)
	assert_eq(simulator.snapshot().loose_card_ids, [3, 1, 2, 0], "点数优先应先比较点数，同点数按方梅红黑")
	simulator.request_sort(TongitsHandServerSimulator.SortMode.SUIT_RANK)
	assert_eq(simulator.snapshot().loose_card_ids, [2, 3, 0, 1], "花色优先应按方梅红黑，同花色内按 A-K")

func test_sort_mode_also_reorders_cards_inside_groups() -> void:
	var simulator := TongitsHandServerSimulator.new()
	_configure_cards(simulator, [
		TongitsCard.new(TongitsCard.Suit.HEARTS, 5, 0),
		TongitsCard.new(TongitsCard.Suit.SPADES, 3, 1),
		TongitsCard.new(TongitsCard.Suit.DIAMONDS, 5, 2),
		TongitsCard.new(TongitsCard.Suit.CLUBS, 3, 3),
	])
	simulator.create_group([0, 1, 2, 3])
	simulator.request_sort(TongitsHandServerSimulator.SortMode.RANK_SUIT)
	assert_eq(simulator.snapshot().groups[0].card_ids, [3, 1, 2, 0], "点数优先也应重排组内卡牌")
	simulator.request_sort(TongitsHandServerSimulator.SortMode.SUIT_RANK)
	assert_eq(simulator.snapshot().groups[0].card_ids, [2, 3, 0, 1], "花色优先也应重排组内卡牌")

func _configure_cards(simulator: TongitsHandServerSimulator, cards: Array[TongitsCard]) -> void:
	simulator._cards.clear()
	simulator._groups.clear()
	simulator._loose_card_ids.clear()
	simulator._next_group_id = 1
	simulator._sort_mode = TongitsHandServerSimulator.SortMode.RANK_SUIT
	simulator._auto_arrange_enabled = false
	for card in cards:
		simulator._cards[card.card_id] = card
		simulator._loose_card_ids.append(card.card_id)
