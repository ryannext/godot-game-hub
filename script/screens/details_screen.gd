extends MarginContainer

# 详情页只发送用户意图，收藏和启动动作交给对应服务处理。
signal back_requested
signal play_requested(game_id: StringName)

var _game: GameDefinition
@onready var _registry: GameRegistryService = get_node("/root/GameRegistry") as GameRegistryService

func _ready() -> void:
	%BackButton.pressed.connect(func(): back_requested.emit())
	%PlayButton.pressed.connect(_on_play_pressed)
	%FavoriteButton.pressed.connect(_on_favorite_pressed)

func show_game(game_id: StringName) -> void:
	# 使用稳定 ID 再查一次目录，避免持有热重载前的 Resource 引用。
	_game = _registry.get_game(game_id)
	if _game == null:
		return
	%GameIcon.texture = _game.icon
	%GameIcon.modulate = _game.accent_color
	%Title.text = _game.title
	%Category.text = "%s · v%s" % [_game.category, _game.version]
	%Description.text = _game.description
	%Tags.text = "  ".join(_game.tags)
	%PlayButton.text = "开始游戏" if _game.is_launchable() else _game.availability_text()
	%PlayButton.disabled = not _game.is_launchable()
	_update_favorite_button()

func _on_play_pressed() -> void:
	if _game != null:
		play_requested.emit(_game.id)

func _on_favorite_pressed() -> void:
	if _game != null:
		_registry.toggle_favorite(_game.id)
		_update_favorite_button()

func _update_favorite_button() -> void:
	%FavoriteButton.text = "★ 已收藏" if _registry.is_favorite(_game.id) else "☆ 收藏"
