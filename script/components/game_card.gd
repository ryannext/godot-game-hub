class_name GameCard
extends Button

# 卡片只负责展示目录数据并上报 ID，不承担页面跳转逻辑。
signal game_selected(game_id: StringName)

var definition: GameDefinition

func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(288, 190)
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func configure(game: GameDefinition) -> void:
	# 运行时配置允许首页与游戏库复用同一个轻量组件。
	definition = game
	text = "%s\n\n%s\n%s" % [game.title, game.category, game.availability_text()]
	icon = game.icon
	add_theme_constant_override("icon_max_width", 72)
	add_theme_color_override("icon_normal_color", game.accent_color)
	add_theme_color_override("icon_hover_color", game.accent_color.lightened(0.12))
	tooltip_text = game.description

func _on_pressed() -> void:
	if definition != null:
		game_selected.emit(definition.id)
