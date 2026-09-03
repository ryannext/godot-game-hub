extends "res://addons/gamehub_sdk/game_module.gd"

# 当前阶段只模拟自己的手牌。所有按钮仍通过本地权威模拟器执行，不直接改 HandView。
@onready var hand_view: TongitsHandView = %HandView
@onready var auto_arrange_button: Button = %AutoArrangeButton
@onready var sort_rule_button: Button = %SortRuleButton
@onready var discard_button: Button = %DiscardButton
@onready var play_meld_button: Button = %PlayMeldButton
@onready var group_action_button: Button = %GroupActionButton
@onready var layoff_button: Button = %LayoffButton
@onready var draw_button: Button = %DrawButton
@onready var opponent_left_meld_area: TongitsMeldAreaView = %OpponentLeftMeldArea
@onready var opponent_right_meld_area: TongitsMeldAreaView = %OpponentRightMeldArea
@onready var player_meld_area: TongitsMeldAreaView = %PlayerMeldArea
@onready var deck_area: Control = %DeckArea
@onready var deck_count_label: Label = %DeckCountLabel

const DEAL_RESET_DELAY_SECONDS := 1.0

var _server := TongitsHandServerSimulator.new()
var _started := false
var _shutdown := false
var _selected_loose_ids: Array[int] = []
var _selected_group_id := -1
var _deal_counter := 0
var _deck_remaining_count := 0
var _deal_request_generation := 0

func _ready() -> void:
	%ExitButton.pressed.connect(func(): exit_requested.emit())
	%RedealButton.pressed.connect(_deal_hand)
	auto_arrange_button.toggled.connect(_on_auto_arrange_toggled)
	sort_rule_button.pressed.connect(_server.toggle_sort_mode)
	play_meld_button.pressed.connect(_on_play_meld_pressed)
	group_action_button.pressed.connect(_on_group_action_pressed)
	hand_view.selection_changed.connect(_on_selection_changed)
	hand_view.move_card_requested.connect(_server.move_card)
	hand_view.last_deal_card_started.connect(_on_last_deal_card_started)
	_server.snapshot_changed.connect(_on_snapshot_changed)
	_server.command_rejected.connect(_on_command_rejected)

	# F6 直跑时没有 GameHost 调用生命周期，因此由当前场景自行启动。
	if get_tree().current_scene == self:
		exit_requested.connect(func(): get_tree().quit())
		initialize(TongitsBoot.launch_context)
		start_game()

func initialize(context: Dictionary) -> void:
	super.initialize(context)
	var embedded := bool(game_context.get("embedded", false))
	print("[TongitsMain] launch mode: %s" % ("embedded" if embedded else "standalone"))
	if StringName(game_context.get("game_id", &"tongits")) != &"tongits":
		push_warning("GameHub game id 与 Tongits 不匹配")

func start_game() -> void:
	if _started:
		return
	_started = true
	_shutdown = false
	_initialize_empty_table()
	print("[TongitsMain] local hand simulator ready")
	ready_to_play.emit()

func shutdown_game() -> void:
	if _shutdown:
		return
	_shutdown = true
	_started = false
	_deal_request_generation += 1
	print("[TongitsMain] shutdown complete")

func _deal_hand() -> void:
	# 重复点击会取消上一次尚未开始的等待，并从新的空桌状态重新计时。
	_deal_request_generation += 1
	var request_generation := _deal_request_generation
	_initialize_empty_table()
	await get_tree().create_timer(DEAL_RESET_DELAY_SECONDS).timeout
	if _shutdown or not _started or request_generation != _deal_request_generation:
		return

	_deal_counter += 1
	hand_view.prepare_deal_animation()
	# 固定基础 seed 加计数既方便复现，也能让“重新发牌”得到不同手牌。
	_server.start_deal(20260828 + _deal_counter)
	_show_test_melds()

func _initialize_empty_table() -> void:
	# 空桌阶段不保留上一局手牌、发牌层、弃牌占位或牌数徽章。
	deck_area.call("set_card_count", 0, false)
	deck_area.visible = false
	_deck_remaining_count = 0
	opponent_left_meld_area.clear_melds()
	opponent_right_meld_area.clear_melds()
	player_meld_area.clear_melds()
	_server.reset_table()

func _show_test_melds() -> void:
	# 三个区域使用固定的有效牌组，专门用于观察方向、重叠距离和换行效果。
	opponent_left_meld_area.apply_snapshot(_build_test_meld_snapshot([
		[[TongitsCard.Suit.DIAMONDS, 3], [TongitsCard.Suit.CLUBS, 3], [TongitsCard.Suit.SPADES, 3]],
		[[TongitsCard.Suit.DIAMONDS, 5], [TongitsCard.Suit.CLUBS, 5], [TongitsCard.Suit.HEARTS, 5], [TongitsCard.Suit.SPADES, 5]],
		[[TongitsCard.Suit.HEARTS, 8], [TongitsCard.Suit.HEARTS, 9], [TongitsCard.Suit.HEARTS, 10]],
		[[TongitsCard.Suit.DIAMONDS, 1], [TongitsCard.Suit.CLUBS, 1], [TongitsCard.Suit.HEARTS, 1], [TongitsCard.Suit.SPADES, 1]],
		[[TongitsCard.Suit.DIAMONDS, 12], [TongitsCard.Suit.CLUBS, 12], [TongitsCard.Suit.SPADES, 12]],
	], 100))
	opponent_right_meld_area.apply_snapshot(_build_test_meld_snapshot([
		[[TongitsCard.Suit.DIAMONDS, 11], [TongitsCard.Suit.CLUBS, 11], [TongitsCard.Suit.SPADES, 11]],
		[[TongitsCard.Suit.DIAMONDS, 9], [TongitsCard.Suit.HEARTS, 9], [TongitsCard.Suit.SPADES, 9]],
		[[TongitsCard.Suit.CLUBS, 1], [TongitsCard.Suit.CLUBS, 2], [TongitsCard.Suit.CLUBS, 3], [TongitsCard.Suit.CLUBS, 4]],
		[[TongitsCard.Suit.DIAMONDS, 8], [TongitsCard.Suit.CLUBS, 8], [TongitsCard.Suit.HEARTS, 8], [TongitsCard.Suit.SPADES, 8]],
		[[TongitsCard.Suit.DIAMONDS, 6], [TongitsCard.Suit.DIAMONDS, 7], [TongitsCard.Suit.DIAMONDS, 8]],
	], 200))
	player_meld_area.apply_snapshot(_build_test_meld_snapshot([
		[[TongitsCard.Suit.DIAMONDS, 6], [TongitsCard.Suit.CLUBS, 6], [TongitsCard.Suit.SPADES, 6]],
		[[TongitsCard.Suit.DIAMONDS, 13], [TongitsCard.Suit.HEARTS, 13], [TongitsCard.Suit.SPADES, 13]],
		[[TongitsCard.Suit.DIAMONDS, 4], [TongitsCard.Suit.CLUBS, 4], [TongitsCard.Suit.SPADES, 4]],
	], 300))

func _build_test_meld_snapshot(meld_specs: Array, first_card_id: int) -> Dictionary:
	var cards: Array[Dictionary] = []
	var groups: Array[Dictionary] = []
	var next_card_id := first_card_id
	for meld_index in meld_specs.size():
		var card_ids: Array[int] = []
		for card_spec: Array in meld_specs[meld_index]:
			cards.append({
				"card_id": next_card_id,
				"suit": int(card_spec[0]),
				"rank": int(card_spec[1]),
			})
			card_ids.append(next_card_id)
			next_card_id += 1
		groups.append({"group_id": meld_index + 1, "card_ids": card_ids})
	return {"cards": cards, "groups": groups}

func _on_snapshot_changed(snapshot: Dictionary) -> void:
	hand_view.apply_snapshot(snapshot)
	var mode := int(snapshot.sort_mode)
	_deck_remaining_count = int(snapshot.get("deck_remaining_count", 0))
	deck_count_label.text = str(_deck_remaining_count)
	auto_arrange_button.set_pressed_no_signal(bool(snapshot.get("auto_arrange_enabled", true)))
	sort_rule_button.text = "点数优先" if mode == TongitsHandServerSimulator.SortMode.RANK_SUIT else "花色优先"
	_update_action_buttons()

func _on_last_deal_card_started() -> void:
	# 第 13 张牌开始起飞时，在同一牌堆节点按快照真实生成剩余的 15 层牌背。
	deck_area.visible = _deck_remaining_count > 0
	deck_area.call("set_card_count", _deck_remaining_count, true)

func _on_selection_changed(loose_card_ids: Array, selected_group_id: int) -> void:
	_selected_loose_ids.assign(loose_card_ids)
	_selected_group_id = selected_group_id
	_update_action_buttons()

func _on_auto_arrange_toggled(enabled: bool) -> void:
	# 开启自动排列时，先通知视图把下一份组合快照用“收拢再展开”呈现。
	if enabled:
		hand_view.prepare_arrange_animation()
	_server.request_auto_arrange(enabled)

func _on_group_action_pressed() -> void:
	if _selected_group_id >= 0:
		_server.dissolve_group(_selected_group_id)
	elif _selected_loose_ids.size() >= 2:
		_server.create_group(_selected_loose_ids)

func _on_play_meld_pressed() -> void:
	if _selected_group_id < 0:
		return
	var played_meld := _server.play_group(_selected_group_id)
	if played_meld.is_empty():
		return
	player_meld_area.append_meld(played_meld.get("cards", []), true)

func _update_action_buttons() -> void:
	# 没有对应牌局上下文的操作必须保持禁用，不能只靠按钮外观暗示可操作。
	discard_button.disabled = _selected_group_id >= 0 or _selected_loose_ids.size() != 1
	play_meld_button.disabled = _selected_group_id < 0
	layoff_button.disabled = true
	draw_button.disabled = true

	if _selected_group_id >= 0:
		group_action_button.text = "解散组"
		group_action_button.disabled = false
	else:
		group_action_button.text = "成组"
		group_action_button.disabled = _selected_loose_ids.size() < 2

func _on_command_rejected(message: String) -> void:
	hand_view.reject_pending_move()
	push_warning("[TongitsHand] %s" % message)

func hand_snapshot() -> Dictionary:
	# 开发工具和集成测试通过只读快照观察状态，不直接取得模拟器内部数组。
	return _server.snapshot()
