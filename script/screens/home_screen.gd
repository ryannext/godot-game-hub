extends ScrollContainer

# HomeScreen 通过信号请求导航，使它不依赖具体的 Main 实现。
signal game_selected(game_id: StringName)
signal library_requested

@onready var featured_grid: HFlowContainer = %FeaturedGrid
@onready var _registry: GameRegistryService = get_node("/root/GameRegistry") as GameRegistryService

func _ready() -> void:
	%BrowseButton.pressed.connect(func(): library_requested.emit())
	_registry.catalog_changed.connect(refresh)
	refresh()

func refresh() -> void:
	# 刷新前释放旧卡片，确保目录热重载不会产生重复项。
	for child in featured_grid.get_children():
		child.queue_free()
	for game in _registry.get_featured_games():
		var card := GameCard.new()
		card.configure(game)
		card.game_selected.connect(func(game_id: StringName): game_selected.emit(game_id))
		featured_grid.add_child(card)
