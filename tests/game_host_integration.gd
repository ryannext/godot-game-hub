extends Node

# 独立集成场景验证真实的 GameHost 生命周期，不依赖鼠标坐标或编辑器焦点。
const HUB_SCENE := preload("res://scene/hub/main.tscn")
const CARD_ART_LIBRARY := preload("res://games/tongits/script/ui/card_art_library.gd")
const ITERATIONS := 10

func _ready() -> void:
	await get_tree().process_frame
	var registry := get_node("/root/GameRegistry") as GameRegistryService
	registry.ensure_loaded()
	var definition := registry.get_game(&"tongits")
	if definition == null:
		_fail("GameRegistry 未发现 Tongits")
		return
	if not _validate_card_atlas():
		return
	if not _validate_group_rules():
		return
	if not _validate_hand_simulator():
		return

	var hub := HUB_SCENE.instantiate()
	add_child(hub)
	await get_tree().process_frame
	var game_host := hub.get_node("GameHost")
	var module_container := game_host.get_node("ModuleContainer")
	var page_margin := hub.get_node("PageMargin") as Control

	for iteration in ITERATIONS:
		await game_host.launch_game(definition, {
			"game_id": &"tongits",
			"locale": "zh_CN",
			"data_directory": "user://games/tongits",
			"embedded": true,
		})
		if module_container.get_child_count() != 1:
			_fail("第 %d 次进入后游戏实例数量不为 1" % (iteration + 1))
			return
		if page_margin.visible:
			_fail("第 %d 次进入后大厅界面仍然可见" % (iteration + 1))
			return
		var module := module_container.get_child(0)
		if not module is GameModule:
			_fail("Tongits 根节点没有实现 GameModule")
			return
		if iteration == 0 and not await _validate_hand_ui(module):
			return
		await game_host.close_game({"test_iteration": iteration + 1})
		if module_container.get_child_count() != 0:
			_fail("第 %d 次退出后仍有游戏实例残留" % (iteration + 1))
			return
		if not page_margin.visible:
			_fail("第 %d 次退出后大厅界面没有恢复" % (iteration + 1))
			return

	print("[GameHostTest] PASS iterations=%d" % ITERATIONS)
	get_tree().quit(0)

func _validate_card_atlas() -> bool:
	# 遍历完整牌组，避免图集坐标缺失直到实际发到某张牌时才被发现。
	for suit in TongitsCard.Suit.values():
		for rank in range(1, 14):
			var card := TongitsCard.new(suit, rank)
			var texture: AtlasTexture = CARD_ART_LIBRARY.texture_for(card)
			if texture == null or texture.region.size != Vector2(112, 150):
				_fail("牌面图集缺少 %s" % card.display_name())
				return false
	print("[GameHostTest] poker2 atlas validated cards=52")
	return true

func _validate_group_rules() -> bool:
	var four_aces: Array[TongitsCard] = []
	for suit in TongitsCard.Suit.values():
		four_aces.append(TongitsCard.new(suit, 1))
	var ace_result := TongitsMeldRules.evaluate(four_aces)
	if ace_result.type != TongitsMeldRules.GroupType.SPECIAL or ace_result.special_type != TongitsMeldRules.SpecialType.FOUR_ACES:
		_fail("四张 A 没有识别为特殊牌组")
		return false

	var long_run: Array[TongitsCard] = []
	for rank in range(4, 8):
		long_run.append(TongitsCard.new(TongitsCard.Suit.HEARTS, rank))
	if TongitsMeldRules.evaluate(long_run).type != TongitsMeldRules.GroupType.SPECIAL:
		_fail("四张以上顺子没有识别为特殊牌组")
		return false
	long_run.pop_back()
	if TongitsMeldRules.evaluate(long_run).type != TongitsMeldRules.GroupType.VALID:
		_fail("三张顺子没有识别为普通组合")
		return false
	print("[GameHostTest] hand group rules validated")
	return true

func _validate_hand_simulator() -> bool:
	var simulator := TongitsHandServerSimulator.new()
	simulator.start_deal(12345)
	var state := simulator.snapshot()
	if state.cards.size() != 13 or not bool(state.auto_arrange_enabled) or int(state.deck_remaining_count) != 15:
		_fail("模拟发牌没有生成 13 张牌或默认开启自动排列")
		return false
	if int(state.sort_mode) != TongitsHandServerSimulator.SortMode.RANK_SUIT or not _is_snapshot_sorted(state, TongitsHandServerSimulator.SortMode.RANK_SUIT):
		_fail("默认点数优先排序错误")
		return false

	var groups_before_disable: Array = state.groups.duplicate(true)
	var loose_before_disable: Array = state.loose_card_ids.duplicate()
	simulator.request_auto_arrange(false)
	state = simulator.snapshot()
	if bool(state.auto_arrange_enabled) or state.groups != groups_before_disable or state.loose_card_ids != loose_before_disable:
		_fail("关闭自动排列改变了当前牌组或散牌顺序")
		return false

	simulator.request_sort(TongitsHandServerSimulator.SortMode.SUIT_RANK)
	state = simulator.snapshot()
	if not _is_snapshot_sorted(state, TongitsHandServerSimulator.SortMode.SUIT_RANK):
		_fail("方块、梅花、红心、黑桃花色排序错误")
		return false

	var base_group_count: int = state.groups.size()
	var base_loose_count: int = state.loose_card_ids.size()
	var first_group_ids: Array[int] = [int(state.loose_card_ids[0]), int(state.loose_card_ids[1])]
	simulator.create_group(first_group_ids)
	state = simulator.snapshot()
	if state.groups.size() != base_group_count + 1 or state.loose_card_ids.size() != base_loose_count - 2:
		_fail("成组没有正确移动散牌")
		return false
	var second_group_ids: Array[int] = [int(state.loose_card_ids[0]), int(state.loose_card_ids[1])]
	simulator.create_group(second_group_ids)
	state = simulator.snapshot()
	var second_group_id := int(state.groups[-1].group_id)
	simulator.dissolve_group(second_group_id)
	state = simulator.snapshot()
	if state.groups.size() != base_group_count + 1 or state.loose_card_ids.size() != base_loose_count - 2:
		_fail("解散组没有把卡牌归还散牌区")
		return false
	print("[GameHostTest] local authoritative hand simulator validated")
	return true

func _is_snapshot_sorted(state: Dictionary, mode: int) -> bool:
	var cards := {}
	for card_data: Dictionary in state.cards:
		cards[int(card_data.card_id)] = card_data
	for index in range(1, state.loose_card_ids.size()):
		var left: Dictionary = cards[int(state.loose_card_ids[index - 1])]
		var right: Dictionary = cards[int(state.loose_card_ids[index])]
		var left_suit := int(TongitsHandServerSimulator.SUIT_PRIORITY[int(left.suit)])
		var right_suit := int(TongitsHandServerSimulator.SUIT_PRIORITY[int(right.suit)])
		var ordered := false
		if mode == TongitsHandServerSimulator.SortMode.SUIT_RANK:
			ordered = left_suit < right_suit or (left_suit == right_suit and int(left.rank) <= int(right.rank))
		else:
			ordered = int(left.rank) < int(right.rank) or (int(left.rank) == int(right.rank) and left_suit <= right_suit)
		if not ordered:
			return false
	return true

func _validate_hand_ui(module: Control) -> bool:
	var hand_view := module.get_node("HandView") as TongitsHandView
	var discard_button := module.get_node("ActionBar/DiscardButton") as Button
	var play_meld_button := module.get_node("ActionBar/PlayMeldButton") as Button
	var group_action := module.get_node("ActionBar/GroupActionButton") as Button
	var layoff_button := module.get_node("ActionBar/LayoffButton") as Button
	var draw_button := module.get_node("ActionBar/DrawButton") as Button
	for button_name in ["DiscardButton", "PlayMeldButton", "LayoffButton", "DrawButton"]:
		if not module.has_node("ActionBar/%s" % button_name):
			_fail("操作区缺少按钮：%s" % button_name)
			return false
	if module.has_node("ActionBar/MoveLeftButton") or module.has_node("ActionBar/MoveRightButton"):
		_fail("操作区仍然保留牌组左右移动按钮")
		return false
	var auto_arrange := module.get_node("SortControlBar/AutoArrangeButton") as Button
	var sort_rule := module.get_node("SortControlBar/SortRuleButton") as Button
	var initial_state: Dictionary = module.hand_snapshot()
	if not initial_state.cards.is_empty():
		_fail("进入牌桌时没有保持空桌状态")
		return false
	if not auto_arrange.button_pressed or sort_rule.text != "点数优先":
		_fail("自动排列或默认点数优先按钮状态错误")
		return false
	if not discard_button.disabled or not play_meld_button.disabled or not group_action.disabled or not layoff_button.disabled or not draw_button.disabled:
		_fail("未选牌时操作按钮没有全部禁用")
		return false
	(module.get_node("RedealButton") as Button).pressed.emit()
	await get_tree().create_timer(1.1).timeout
	await get_tree().process_frame
	initial_state = module.hand_snapshot()
	if initial_state.cards.size() != 13:
		_fail("点击测试发牌并等待后没有生成 13 张手牌")
		return false
	if (
		module.get_node("OpponentLeftMeldArea").get_child_count() != 17
		or module.get_node("OpponentRightMeldArea").get_child_count() != 17
		or module.get_node("PlayerMeldArea").get_child_count() != 9
	):
		_fail("测试发牌没有向三个 MeldArea 生成预期的测试牌组")
		return false
	var initial_group_count: int = initial_state.groups.size()
	var selected_ids: Array = initial_state.loose_card_ids.slice(0, 2)
	hand_view._on_card_tapped(int(selected_ids[0]))
	if discard_button.disabled or not group_action.disabled:
		_fail("选中一张散牌时弃牌按钮或成组按钮状态错误")
		return false
	hand_view._on_card_tapped(int(selected_ids[1]))
	if not discard_button.disabled:
		_fail("选中多张散牌时弃牌按钮仍然启用")
		return false
	if group_action.disabled or group_action.text != "成组":
		_fail("选中两张散牌后成组按钮没有启用")
		return false
	group_action.pressed.emit()
	await get_tree().process_frame
	var grouped_state: Dictionary = module.hand_snapshot()
	if grouped_state.groups.size() != initial_group_count + 1:
		_fail("手牌 UI 成组操作没有生成新组")
		return false

	var grouped_card_id := int(grouped_state.groups[-1].card_ids[0])
	hand_view._on_card_tapped(grouped_card_id)
	if group_action.disabled or group_action.text != "解散组" or play_meld_button.disabled:
		_fail("选中牌组后解散或打牌组按钮没有启用")
		return false
	var player_meld_count_before := module.get_node("PlayerMeldArea").get_child_count()
	play_meld_button.pressed.emit()
	await get_tree().process_frame
	var played_state: Dictionary = module.hand_snapshot()
	if played_state.groups.size() != initial_group_count or played_state.cards.size() != 11:
		_fail("打牌组没有从手牌移除所选牌组")
		return false
	if module.get_node("PlayerMeldArea").get_child_count() != player_meld_count_before + 2:
		_fail("打出的牌组没有添加到玩家 MeldArea")
		return false

	# 直接驱动手势控制器验证：长按只拖单张，且不改变用户选择的排序规则。
	var drag_state: Dictionary = module.hand_snapshot()
	var drag_card_id := int(drag_state.loose_card_ids[0])
	hand_view._on_card_tapped(drag_card_id)
	var start := hand_view.get_global_transform_with_canvas() * Vector2(180, 100)
	var finish := hand_view.get_global_transform_with_canvas() * Vector2(900, 100)
	hand_view._on_card_drag_started(drag_card_id, start)
	hand_view._on_card_drag_moved(drag_card_id, finish)
	hand_view._on_card_drag_ended(drag_card_id, finish)
	await get_tree().process_frame
	var moved_state: Dictionary = module.hand_snapshot()
	if moved_state.cards.size() != 11 or int(moved_state.sort_mode) != TongitsHandServerSimulator.SortMode.RANK_SUIT:
		_fail("单张长按拖拽改变了当前点数优先规则")
		return false
	print("[GameHostTest] mobile hand UI interactions validated")
	return true

func _fail(message: String) -> void:
	push_error("[GameHostTest] FAIL %s" % message)
	get_tree().quit(1)
