class_name GameHost
extends Control

# GameHost 是大厅与游戏模块之间唯一的场景边界，负责加载、生命周期和清理。
const GAME_MODULE_SCRIPT := preload("res://addons/gamehub_sdk/game_module.gd")

signal game_started(game_id: StringName)
signal game_closed(game_id: StringName, result: Dictionary)
signal load_failed(game_id: StringName, message: String)

@onready var module_container: Control = %ModuleContainer
@onready var loading_layer: Control = %LoadingLayer
@onready var loading_label: Label = %LoadingLabel
@onready var loading_progress: ProgressBar = %LoadingProgress

var _current_game: Control
var _current_definition: GameDefinition
var _load_progress: Array = []
var _is_transitioning := false

func launch_game(definition: GameDefinition, context: Dictionary) -> void:
	if _is_transitioning or _current_game != null:
		load_failed.emit(definition.id, "已有游戏正在运行或切换中")
		return
	if not definition.is_launchable():
		load_failed.emit(definition.id, "游戏入口尚未配置")
		return

	_is_transitioning = true
	_current_definition = definition
	visible = true
	loading_layer.visible = true
	loading_label.text = "正在加载 %s…" % definition.title
	loading_progress.value = 0.0

	if definition.delivery_mode == GameDefinition.DeliveryMode.PCK:
		var pack_error := _mount_pack(definition)
		if not pack_error.is_empty():
			_fail_launch(pack_error)
			return

	var request_error := ResourceLoader.load_threaded_request(definition.entry_scene_path, "PackedScene")
	if request_error != OK:
		_fail_launch("资源加载请求失败：%s" % error_string(request_error))
		return

	while true:
		var status := ResourceLoader.load_threaded_get_status(definition.entry_scene_path, _load_progress)
		loading_progress.value = 0.0 if _load_progress.is_empty() else float(_load_progress[0]) * 100.0
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_launch("游戏场景异步加载失败")
			return
		await get_tree().process_frame

	var packed_scene := ResourceLoader.load_threaded_get(definition.entry_scene_path) as PackedScene
	if packed_scene == null:
		_fail_launch("游戏入口不是有效的 PackedScene")
		return
	var instance := packed_scene.instantiate()
	if not is_instance_of(instance, GAME_MODULE_SCRIPT):
		instance.queue_free()
		_fail_launch("游戏根节点必须继承 GameModule")
		return

	_current_game = instance as Control
	_current_game.exit_requested.connect(_on_exit_requested)
	_current_game.game_finished.connect(_on_game_finished)
	module_container.add_child(_current_game)
	_current_game.initialize(context)
	_current_game.start_game()
	loading_layer.visible = false
	_is_transitioning = false
	game_started.emit(definition.id)

func close_game(result: Dictionary = {}) -> void:
	if _is_transitioning or _current_game == null:
		return
	_is_transitioning = true
	var closing_id := _current_definition.id
	_current_game.shutdown_game()
	_current_game.queue_free()
	_current_game = null
	_current_definition = null
	await get_tree().process_frame
	visible = false
	_is_transitioning = false
	game_closed.emit(closing_id, result)

func _mount_pack(definition: GameDefinition) -> String:
	if definition.pack_path.is_empty():
		return "PCK 发布模式缺少 pack_path"
	var absolute_path := definition.pack_path
	if not absolute_path.is_absolute_path():
		absolute_path = OS.get_executable_path().get_base_dir().path_join(absolute_path)
	if not FileAccess.file_exists(absolute_path):
		return "找不到游戏资源包：%s" % absolute_path
	# false 禁止游戏包覆盖 Hub 中的同名资源。
	if not ProjectSettings.load_resource_pack(absolute_path, false):
		return "游戏资源包挂载失败：%s" % absolute_path
	return ""

func _fail_launch(message: String) -> void:
	var failed_id := _current_definition.id if _current_definition != null else &""
	push_error("[GameHost] %s" % message)
	_current_definition = null
	_is_transitioning = false
	visible = false
	load_failed.emit(failed_id, message)

func _on_exit_requested() -> void:
	close_game({"reason": "user_exit"})

func _on_game_finished(result: Dictionary) -> void:
	close_game(result)
