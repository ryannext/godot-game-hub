class_name GameRegistryService
extends Node

# Hub 的游戏目录服务。它只读取游戏元数据，不加载独立游戏的实际内容。
signal catalog_changed
signal favorite_changed(game_id: StringName, is_favorite: bool)

const CATALOG_DIRECTORY := "res://resources/games"
const MODULES_DIRECTORY := "res://games"

var _games: Array[GameDefinition] = []
var _favorites: Dictionary = {}
var is_loaded := false

func _ready() -> void:
	# 故意延迟加载：Boot 场景负责触发目录初始化并展示对应进度。
	pass

func reload_catalog() -> void:
	# 每次都从磁盘重建快照，避免热更新后残留已经删除的条目。
	_games.clear()
	is_loaded = false
	var catalog_directory := DirAccess.open(CATALOG_DIRECTORY)
	if catalog_directory == null:
		push_warning("Game catalog directory was not found: %s" % CATALOG_DIRECTORY)
	else:
		for file_name in catalog_directory.get_files():
			if file_name.ends_with(".tres"):
				_add_definition(CATALOG_DIRECTORY.path_join(file_name))

	# 每个内嵌游戏通过自己目录中的 module.tres 自注册。
	var modules_directory := DirAccess.open(MODULES_DIRECTORY)
	if modules_directory != null:
		for directory_name in modules_directory.get_directories():
			var manifest_path := MODULES_DIRECTORY.path_join(directory_name).path_join("module.tres")
			if ResourceLoader.exists(manifest_path):
				_add_definition(manifest_path)

	_games.sort_custom(func(a: GameDefinition, b: GameDefinition): return a.title < b.title)
	is_loaded = true
	catalog_changed.emit()

func _add_definition(resource_path: String) -> void:
	var definition := load(resource_path) as GameDefinition
	if definition == null or definition.id.is_empty():
		push_warning("Invalid game definition: %s" % resource_path)
		return
	# 游戏 ID 是存档、收藏和未来启动协议的主键，必须保持唯一。
	if get_game(definition.id) != null:
		push_warning("Duplicate game id: %s" % definition.id)
		return
	_games.append(definition)

func ensure_loaded() -> void:
	# 页面也可以安全调用，防止开发者绕过 Boot 直接运行大厅场景。
	if not is_loaded:
		reload_catalog()

func get_games() -> Array[GameDefinition]:
	# 返回副本，避免页面意外修改注册表内部数组。
	return _games.duplicate()

func get_featured_games(limit := 3) -> Array[GameDefinition]:
	var result: Array[GameDefinition] = []
	for game in _games:
		result.append(game)
		if result.size() >= limit:
			break
	return result

func get_game(game_id: StringName) -> GameDefinition:
	for game in _games:
		if game.id == game_id:
			return game
	return null

func search(query: String, category := "全部") -> Array[GameDefinition]:
	# 当前是本地轻量搜索；游戏数量增大后可替换为预构建索引。
	var normalized_query := query.strip_edges().to_lower()
	var result: Array[GameDefinition] = []
	for game in _games:
		if category != "全部" and game.category != category:
			continue
		var searchable := "%s %s %s" % [game.title, game.description, " ".join(game.tags)]
		if normalized_query.is_empty() or searchable.to_lower().contains(normalized_query):
			result.append(game)
	return result

func get_categories() -> PackedStringArray:
	var categories := PackedStringArray(["全部"])
	for game in _games:
		if not categories.has(game.category):
			categories.append(game.category)
	return categories

func is_favorite(game_id: StringName) -> bool:
	return _favorites.get(game_id, false)

func toggle_favorite(game_id: StringName) -> bool:
	# MVP 仅保存在内存；后续由用户数据服务负责持久化。
	var next_value := not is_favorite(game_id)
	_favorites[game_id] = next_value
	favorite_changed.emit(game_id, next_value)
	return next_value
