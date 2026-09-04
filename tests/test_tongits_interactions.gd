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

func test_hand_group_gap_stays_fixed_when_card_step_compresses() -> void:
	var view := track(TongitsHandView.new()) as TongitsHandView
	view._groups = [
		{"group_id": 1, "card_ids": [0, 1, 2]},
		{"group_id": 2, "card_ids": [3, 4, 5]},
	]
	view._loose_card_ids = []
	view.size = Vector2(1000.0, 200.0)
	var wide_layout := view._calculate_layout(&"", -1, -1)
	var wide_gap: float = wide_layout.card_positions[3].x - wide_layout.card_positions[2].x - TongitsHandView.CARD_SIZE.x
	view.size = Vector2(500.0, 200.0)
	var compact_layout := view._calculate_layout(&"", -1, -1)
	var compact_gap: float = compact_layout.card_positions[3].x - compact_layout.card_positions[2].x - TongitsHandView.CARD_SIZE.x
	assert_true(is_equal_approx(wide_gap, TongitsHandView.GROUP_GAP), "宽布局的牌组边缘间距应使用固定值")
	assert_true(is_equal_approx(compact_gap, TongitsHandView.GROUP_GAP), "压缩牌距后牌组边缘间距仍应保持不变")
	assert_true(float(compact_layout.card_step) < float(wide_layout.card_step), "空间不足时应只压缩组内牌距")

func test_meld_areas_follow_each_players_inward_flow() -> void:
	var view := track(TongitsMeldAreaView.new()) as TongitsMeldAreaView
	view.size = Vector2(350, 220)
	view.card_size = Vector2(50, 70)
	view.card_step = 30.0
	view.horizontal_padding = 10.0
	view.vertical_padding = 10.0
	view.meld_gap = 20.0
	view.wrap_melds = true
	var left_layout := view.calculate_layout([3, 2, 4])
	assert_true(left_layout[0][0].x < left_layout[0][1].x, "左侧对手牌组应从左向右展开")
	assert_eq(left_layout[0][0].y, left_layout[1][0].y, "同一行放得下时多个牌组应连续排列")
	assert_true(left_layout[2][0].y > left_layout[1][0].y, "当前行放不下完整牌组时应整体换行")

	view.flow_direction = TongitsMeldAreaView.FlowDirection.RIGHT_TO_LEFT
	var right_layout := view.calculate_layout([3, 2, 4])
	assert_true(right_layout[0][0].x > right_layout[0][1].x, "右侧对手牌组应从右向左展开")

	view.flow_direction = TongitsMeldAreaView.FlowDirection.LEFT_TO_RIGHT
	view.size = Vector2(500, 100)
	var player_layout := view.calculate_layout([3, 3])
	assert_eq(player_layout[0][0].y, player_layout[1][0].y, "玩家的多个牌组应处于同一行")
	assert_true(player_layout[1][0].x > player_layout[0][-1].x, "玩家牌组应按组从左向右排列")

	view.set_melds(
		[{"group_id": 1, "card_ids": [10, 11, 12]}, {"group_id": 2, "card_ids": [13, 14]}],
		[
			{"card_id": 10, "suit": TongitsCard.Suit.CLUBS, "rank": 3},
			{"card_id": 11, "suit": TongitsCard.Suit.DIAMONDS, "rank": 3},
			{"card_id": 12, "suit": TongitsCard.Suit.HEARTS, "rank": 3},
			{"card_id": 13, "suit": TongitsCard.Suit.SPADES, "rank": 7},
			{"card_id": 14, "suit": TongitsCard.Suit.SPADES, "rank": 8},
		]
	)
	assert_eq(view.get_child_count(), 5, "MeldArea 应按快照为每张牌创建桌面卡牌视图")

	view.flow_direction = TongitsMeldAreaView.FlowDirection.RIGHT_TO_LEFT
	view.set_melds(
		[{"group_id": 1, "card_ids": [20, 21, 22]}],
		[
			{"card_id": 20, "suit": TongitsCard.Suit.CLUBS, "rank": 8},
			{"card_id": 21, "suit": TongitsCard.Suit.DIAMONDS, "rank": 8},
			{"card_id": 22, "suit": TongitsCard.Suit.HEARTS, "rank": 8},
		]
	)
	assert_true(view.get_child(0).z_index > view.get_child(2).z_index, "右侧牌组应让屏幕右边的牌覆盖左边的牌")

func test_play_group_removes_cards_from_hand() -> void:
	var simulator := TongitsHandServerSimulator.new()
	_configure_cards(simulator, [
		TongitsCard.new(TongitsCard.Suit.DIAMONDS, 7, 0),
		TongitsCard.new(TongitsCard.Suit.CLUBS, 7, 1),
		TongitsCard.new(TongitsCard.Suit.SPADES, 7, 2),
	])
	simulator.create_group([0, 1, 2])
	var group_id := int(simulator.snapshot().groups[0].group_id)
	var played := simulator.play_group(group_id)
	var state := simulator.snapshot()
	assert_eq(played.cards.size(), 3, "打牌组应返回用于 MeldArea 展示的三张牌")
	assert_true(state.cards.is_empty(), "打出的牌不应继续留在手牌数据中")
	assert_true(state.groups.is_empty(), "打出的牌组不应继续留在手牌牌组中")

func test_discard_removes_only_a_loose_card() -> void:
	var simulator := TongitsHandServerSimulator.new()
	_configure_cards(simulator, [
		TongitsCard.new(TongitsCard.Suit.DIAMONDS, 7, 0),
		TongitsCard.new(TongitsCard.Suit.CLUBS, 7, 1),
		TongitsCard.new(TongitsCard.Suit.SPADES, 7, 2),
		TongitsCard.new(TongitsCard.Suit.HEARTS, 9, 3),
	])
	simulator.create_group([0, 1, 2])
	var rejected_group_card := simulator.discard_card(0)
	assert_true(rejected_group_card.is_empty(), "牌组中的牌不能通过单张弃牌操作打出")
	var discarded := simulator.discard_card(3)
	var state := simulator.snapshot()
	assert_eq(int(discarded.card_id), 3, "弃牌命令应返回被打出的牌面数据")
	assert_false(state.cards.any(func(card: Dictionary) -> bool: return int(card.card_id) == 3), "弃牌后手牌数据不应继续包含该牌")
	assert_false(state.loose_card_ids.has(3), "弃牌后散牌顺序不应继续包含该牌")
	assert_eq(state.discard_pile.size(), 1, "弃牌快照应记录弃牌历史")
	assert_eq(int(state.discard_pile[-1].card_id), 3, "弃牌历史末尾应为最近打出的牌")

func test_meld_unfold_only_runs_when_explicitly_requested() -> void:
	var view := track(TongitsMeldAreaView.new()) as TongitsMeldAreaView
	view.size = Vector2(500, 100)
	var cards := [
		{"card_id": 30, "suit": TongitsCard.Suit.DIAMONDS, "rank": 7},
		{"card_id": 31, "suit": TongitsCard.Suit.CLUBS, "rank": 7},
		{"card_id": 32, "suit": TongitsCard.Suit.SPADES, "rank": 7},
	]
	view.apply_snapshot({"groups": [{"group_id": 1, "card_ids": [30, 31, 32]}], "cards": cards})
	assert_true(view._unfold_tween == null, "普通快照渲染不应播放展开动画")

	view.clear_melds()
	view.append_meld(cards)
	assert_true(view._unfold_tween == null, "普通追加牌组默认不应播放展开动画")

	view.clear_melds()
	view.append_meld(cards, true)
	assert_true(view._unfold_tween != null, "打出牌组时显式请求展开动画")

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

func test_draw_card_appends_to_hand_end_and_decrements_stock() -> void:
	var simulator := TongitsHandServerSimulator.new()
	simulator.start_deal(20260829)
	var before := simulator.snapshot()
	var drawn := simulator.draw_card()
	var after := simulator.snapshot()
	assert_false(drawn.is_empty(), "牌堆有牌时应能摸到一张真实牌")
	assert_eq(after.cards.size(), before.cards.size() + 1, "摸牌后手牌应增加一张")
	assert_eq(int(after.deck_remaining_count), int(before.deck_remaining_count) - 1, "摸牌后牌堆数量应减一")
	assert_eq(int(after.loose_card_ids[-1]), int(drawn.card_id), "摸到的牌应追加在散牌区最后一位")

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
