extends Control

# Boot 场景必须保持轻量，只引用加载页自身需要的资源。
# 这里使用字符串而不是 preload()，否则大厅会在加载页出现前被同步加载。
const HUB_SCENE_PATH := "res://scene/hub/main.tscn"
const MINIMUM_VISIBLE_SECONDS := 1.25
const LOG_INTERVAL_PERCENT := 10

@onready var progress_bar: ProgressBar = %ProgressBar
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
@onready var registry: GameRegistryService = get_node("/root/GameRegistry") as GameRegistryService

var _started_at_msec := 0
var _progress_state: Array = []
# 目标进度来自真实任务；显示进度通过缓动追赶目标，不能提前超过它。
var _target_progress := 0.0
var _display_progress := 0.0

# 日志状态用于去重，避免每帧或每次加载轮询都打印相同内容。
var _last_logged_display_percent := 0
var _last_logged_target_percent := -1
var _last_logged_stage := ""

func _ready() -> void:
	_started_at_msec = Time.get_ticks_msec()
	progress_bar.value = 0.0
	progress_label.text = "0%"
	await get_tree().process_frame
	await _load_application()

func _process(delta: float) -> void:
	# 最后的 8% 使用更快的速度，既能看见完成动画，也不会拖慢切换。
	var speed := 1.6 if _target_progress >= 1.0 else 0.78
	_display_progress = move_toward(_display_progress, _target_progress, speed * delta)
	progress_bar.value = _display_progress * 100.0
	var display_percent := roundi(progress_bar.value)
	progress_label.text = "%d%%" % display_percent
	var log_bucket := int(display_percent / LOG_INTERVAL_PERCENT) * LOG_INTERVAL_PERCENT
	if log_bucket > _last_logged_display_percent:
		_last_logged_display_percent = log_bucket
		print("[GameHubBoot] display=%d%% target=%d%%" % [
			log_bucket,
			roundi(_target_progress * 100.0),
		])

func _load_application() -> void:
	# 0%~22%：初始化 Hub 自己的轻量游戏目录。
	_set_progress(0.08, "正在初始化游戏目录…")
	registry.ensure_loaded()
	_set_progress(0.22, "已发现 %d 款游戏" % registry.get_games().size())
	await get_tree().process_frame

	# 22%~92%：异步加载大厅场景及其静态依赖（页面、主题和脚本）。
	var request_error := ResourceLoader.load_threaded_request(HUB_SCENE_PATH, "PackedScene")
	if request_error != OK:
		_show_error("大厅资源加载请求失败：%s" % error_string(request_error))
		return

	while true:
		var status := ResourceLoader.load_threaded_get_status(HUB_SCENE_PATH, _progress_state)
		# Godot 返回 0~1 的单资源进度，再映射到本阶段占用的区间。
		var resource_progress := 0.0 if _progress_state.is_empty() else float(_progress_state[0])
		_set_progress(lerpf(0.22, 0.92, resource_progress), "正在加载大厅资源…")

		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_error("大厅资源加载失败")
			return
		await get_tree().process_frame

	# 真实资源已经就绪，但先让显示进度追上，避免视觉上瞬间跳到 100%。
	_set_progress(0.92, "正在完成启动准备…")
	var elapsed_seconds := float(Time.get_ticks_msec() - _started_at_msec) / 1000.0
	if elapsed_seconds < MINIMUM_VISIBLE_SECONDS:
		await get_tree().create_timer(MINIMUM_VISIBLE_SECONDS - elapsed_seconds).timeout
	await _wait_for_displayed_progress(0.915)

	# 只有状态确认 LOADED 后才能取资源；提前调用会阻塞主线程。
	var hub_scene := ResourceLoader.load_threaded_get(HUB_SCENE_PATH) as PackedScene
	if hub_scene == null:
		_show_error("无法创建大厅场景")
		return
	_set_progress(1.0, "准备完成")
	await _wait_for_displayed_progress(0.995)
	await get_tree().process_frame
	get_tree().change_scene_to_packed(hub_scene)

func _set_progress(value: float, message: String) -> void:
	# clampf 的下限使用旧目标，保证任何阶段都不会让进度倒退。
	_target_progress = clampf(value, _target_progress, 1.0)
	status_label.text = message
	var target_percent := roundi(_target_progress * 100.0)
	if target_percent != _last_logged_target_percent or message != _last_logged_stage:
		_last_logged_target_percent = target_percent
		_last_logged_stage = message
		print("[GameHubBoot] target=%d%% stage=%s" % [target_percent, message])

func _wait_for_displayed_progress(value: float) -> void:
	# 等待的是 UI 动画，不是资源加载；真实加载已在上方完成。
	while _display_progress < value:
		await get_tree().process_frame

func _show_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("ff6b83"))
	progress_bar.modulate = Color("ff6b83")
