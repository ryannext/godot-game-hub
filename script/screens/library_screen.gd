extends VBoxContainer

# 游戏库只处理筛选和结果展示，游戏详情由上层路由打开。
signal game_selected(game_id: StringName)

@onready var search_input: LineEdit = %SearchInput
@onready var category_filter: OptionButton = %CategoryFilter
@onready var games_grid: HFlowContainer = %GamesGrid
@onready var _registry: GameRegistryService = get_node("/root/GameRegistry") as GameRegistryService

func _ready() -> void:
	search_input.text_changed.connect(func(_value: String): refresh())
	category_filter.item_selected.connect(func(_index: int): refresh())
	_registry.catalog_changed.connect(_setup_filters)
	_setup_filters()

func _setup_filters() -> void:
	# 目录变化时重建分类，避免保留已经不存在的分类选项。
	category_filter.clear()
	for category in _registry.get_categories():
		category_filter.add_item(category)
	refresh()

func refresh() -> void:
	# 搜索和分类共用一次查询，保持 UI 状态组合生效。
	for child in games_grid.get_children():
		child.queue_free()
	var category := "全部"
	if category_filter.item_count > 0:
		category = category_filter.get_item_text(category_filter.selected)
	var games: Array[GameDefinition] = _registry.search(search_input.text, category)
	%EmptyState.visible = games.is_empty()
	for game in games:
		var card := GameCard.new()
		card.configure(game)
		card.game_selected.connect(func(game_id: StringName): game_selected.emit(game_id))
		games_grid.add_child(card)
