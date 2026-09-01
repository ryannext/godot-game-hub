class_name TongitsBoot
extends Control

# Boot 只负责读取启动上下文和异步装载主场景，避免首帧同步加载完整游戏。
const MAIN_SCENE_PATH := "res://games/tongits/scene/main.tscn"

# 静态上下文跨场景保存；Main 被开发者单独运行时仍会自行创建默认上下文。
static var launch_context := {
	"game_id": &"tongits",
	"locale": "zh_CN",
	"data_directory": "user://games/tongits",
	"embedded": false,
}

@onready var status_label: Label = %StatusLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var mode_label: Label = %ModeLabel

var _load_progress: Array = []

func _ready() -> void:
	mode_label.text = "独立场景调试"
	print("[TongitsBoot] launch_mode=%s locale=%s" % [mode_label.text, launch_context.locale])
	progress_bar.value = 0.0
	await get_tree().process_frame
	await _load_main_scene()

func _load_main_scene() -> void:
	# 字符串路径配合线程加载，确保 Boot 场景本身保持轻量。
	status_label.text = "正在准备 Tongits…"
	var request_error := ResourceLoader.load_threaded_request(MAIN_SCENE_PATH, "PackedScene")
	if request_error != OK:
		_show_error("主场景加载请求失败：%s" % error_string(request_error))
		return

	while true:
		var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, _load_progress)
		progress_bar.value = 0.0 if _load_progress.is_empty() else float(_load_progress[0]) * 100.0
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_error("主场景异步加载失败")
			return
		await get_tree().process_frame

	var main_scene := ResourceLoader.load_threaded_get(MAIN_SCENE_PATH) as PackedScene
	if main_scene == null:
		_show_error("主场景资源无效")
		return
	progress_bar.value = 100.0
	status_label.text = "准备完成"
	print("[TongitsBoot] main scene loaded")
	await get_tree().process_frame
	get_tree().change_scene_to_packed(main_scene)

func _show_error(message: String) -> void:
	# 错误留在 Boot 界面上，便于独立运行和 Hub 启动时直接诊断。
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("ff718d"))
	push_error("[TongitsBoot] %s" % message)
