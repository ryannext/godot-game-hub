extends "res://addons/gamehub_sdk/game_module.gd"

# 当前阶段只模拟自己的手牌。所有按钮仍通过本地权威模拟器执行，不直接改 HandView。
@onready var hand_view: TongitsHandView = %HandView
@onready var auto_arrange_button: Button = %AutoArrangeButton
@onready var sort_rule_button: Button = %SortRuleButton
@onready var group_action_button: Button = %GroupActionButton
@onready var move_left_button: Button = %MoveLeftButton
@onready var move_right_button: Button = %MoveRightButton
@onready var deck_area: Control = %DeckArea
@onready var deck_count_label: Label = %DeckCountLabel

var _server := TongitsHandServerSimulator.new()
var _started := false
var _shutdown := false
var _selected_loose_ids: Array[int] = []
var _selected_group_id := -1
var _deal_counter := 0
var _deck_remaining_count := 0

func _ready() -> void:
	%ExitButton.pressed.connect(func(): exit_requested.emit())
	%RedealButton.pressed.connect(_deal_hand)
	auto_arrange_button.toggled.connect(_on_auto_arrange_toggled)
	sort_rule_button.pressed.connect(_server.toggle_sort_mode)
	group_action_button.pressed.connect(_on_group_action_pressed)
	move_left_button.pressed.connect(func(): _server.move_group(_selected_group_id, -1))
	move_right_button.pressed.connect(func(): _server.move_group(_selected_group_id, 1))
	hand_view.selection_changed.connect(_on_selection_changed)
	hand_view.move_card_requested.connect(_server.move_card)
	hand_view.deal_animation_finished.connect(_on_deal_animation_finished)
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
	_deal_hand()
	print("[TongitsMain] local hand simulator ready")
	ready_to_play.emit()

func shutdown_game() -> void:
	if _shutdown:
		return
	_shutdown = true
	_started = false
	print("[TongitsMain] shutdown complete")

func _deal_hand() -> void:
	_deal_counter += 1
	hand_view.clear_selection()
	# 发牌阶段由实际飞出的牌背组成牌堆；先隐藏上一局的静态剩余牌堆。
	deck_area.visible = false
	hand_view.prepare_deal_animation()
	# 固定基础 seed 加计数既方便复现，也能让“重新发牌”得到不同手牌。
	_server.start_deal(20260828 + _deal_counter)

func _on_snapshot_changed(snapshot: Dictionary) -> void:
	hand_view.apply_snapshot(snapshot)
	var mode := int(snapshot.sort_mode)
	_deck_remaining_count = int(snapshot.get("deck_remaining_count", 0))
	deck_count_label.text = str(_deck_remaining_count)
	auto_arrange_button.set_pressed_no_signal(bool(snapshot.get("auto_arrange_enabled", true)))
	sort_rule_button.text = "点数优先" if mode == TongitsHandServerSimulator.SortMode.RANK_SUIT else "花色优先"
	_update_action_buttons()

func _on_deal_animation_finished() -> void:
	# 发牌完成后按服务端快照重新显示剩余牌堆；没有剩余牌时保持隐藏。
	deck_area.visible = _deck_remaining_count > 0

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

func _update_action_buttons() -> void:
	if _selected_group_id >= 0:
		group_action_button.text = "解散组"
		group_action_button.disabled = false
		var index := hand_view.group_index(_selected_group_id)
		move_left_button.disabled = index <= 0
		move_right_button.disabled = index < 0 or index >= hand_view.group_count() - 1
	else:
		group_action_button.text = "成组"
		group_action_button.disabled = _selected_loose_ids.size() < 2
		move_left_button.disabled = true
		move_right_button.disabled = true

func _on_command_rejected(message: String) -> void:
	hand_view.reject_pending_move()
	push_warning("[TongitsHand] %s" % message)

func hand_snapshot() -> Dictionary:
	# 开发工具和集成测试通过只读快照观察状态，不直接取得模拟器内部数组。
	return _server.snapshot()
