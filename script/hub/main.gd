extends Control

# 页面场景属于大厅资源依赖，会随 main.tscn 的线程加载一起准备完成。
const HOME_SCREEN := preload("res://scene/hub/screens/home_screen.tscn")
const LIBRARY_SCREEN := preload("res://scene/hub/screens/library_screen.tscn")
const DETAILS_SCREEN := preload("res://scene/hub/screens/details_screen.tscn")
const SETTINGS_SCREEN := preload("res://scene/hub/screens/settings_screen.tscn")

@onready var screen_host: Control = %ScreenHost
@onready var page_margin: Control = %PageMargin
@onready var status_label: Label = %StatusLabel
@onready var _registry: GameRegistryService = get_node("/root/GameRegistry") as GameRegistryService
@onready var _game_host: Control = %GameHost

var _current_screen: Control
# 详情页不是侧栏一级页面，返回时需要记住它从哪里进入。
var _previous_screen := "home"

func _ready() -> void:
	_registry.ensure_loaded()
	%HomeButton.pressed.connect(func(): show_screen("home"))
	%LibraryButton.pressed.connect(func(): show_screen("library"))
	%SettingsButton.pressed.connect(func(): show_screen("settings"))
	_game_host.game_started.connect(_on_game_started)
	_game_host.game_closed.connect(_on_game_closed)
	_game_host.load_failed.connect(_on_game_load_failed)
	show_screen("home")
	status_label.text = "%d 款游戏已连接" % _registry.get_games().size()

func show_screen(screen_name: String) -> void:
	# ScreenHost 同一时刻只承载一个一级页面。
	if _current_screen != null:
		_current_screen.queue_free()
	match screen_name:
		"home":
			_current_screen = HOME_SCREEN.instantiate()
			_current_screen.game_selected.connect(show_game_details)
			_current_screen.library_requested.connect(func(): show_screen("library"))
		"library":
			_current_screen = LIBRARY_SCREEN.instantiate()
			_current_screen.game_selected.connect(show_game_details)
		"settings":
			_current_screen = SETTINGS_SCREEN.instantiate()
		_:
			return
	_previous_screen = screen_name
	screen_host.add_child(_current_screen)
	_update_navigation(screen_name)

func show_game_details(game_id: StringName) -> void:
	# 详情页通过游戏 ID 查询注册表，不直接持有卡片节点或列表状态。
	if _current_screen != null:
		_current_screen.queue_free()
	var details := DETAILS_SCREEN.instantiate()
	_current_screen = details
	screen_host.add_child(details)
	details.show_game(game_id)
	details.back_requested.connect(func(): show_screen(_previous_screen))
	details.play_requested.connect(_on_play_requested)
	_update_navigation("")

func _on_play_requested(game_id: StringName) -> void:
	var game: GameDefinition = _registry.get_game(game_id)
	if game == null:
		return
	# 每个游戏只读写自己的 user://games/<id> 目录，避免存档互相污染。
	var data_directory := "user://games/%s" % game.id
	var data_directory_absolute := ProjectSettings.globalize_path(data_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(data_directory_absolute)
	if directory_error != OK:
		_on_game_load_failed(game.id, "无法创建游戏数据目录：%s" % data_directory)
		return
	var context := {
		"game_id": game.id,
		"locale": "zh_CN",
		"data_directory": data_directory,
		"embedded": true,
	}
	_game_host.launch_game(game, context)

func _on_game_started(game_id: StringName) -> void:
	page_margin.visible = false
	%Toast.visible = false
	print("[GameHub] started embedded game: %s" % game_id)

func _on_game_closed(game_id: StringName, result: Dictionary) -> void:
	page_margin.visible = true
	%ToastLabel.text = "%s 已退出" % game_id
	%Toast.visible = true
	get_tree().create_timer(2.0).timeout.connect(func(): %Toast.visible = false)
	print("[GameHub] closed embedded game: %s result=%s" % [game_id, result])

func _on_game_load_failed(_game_id: StringName, message: String) -> void:
	page_margin.visible = true
	%ToastLabel.text = message
	%Toast.visible = true
	get_tree().create_timer(3.0).timeout.connect(func(): %Toast.visible = false)

func _update_navigation(active: String) -> void:
	# 禁用当前入口同时承担“选中态”视觉效果，并阻止重复创建同一页面。
	%HomeButton.disabled = active == "home"
	%LibraryButton.disabled = active == "library"
	%SettingsButton.disabled = active == "settings"
