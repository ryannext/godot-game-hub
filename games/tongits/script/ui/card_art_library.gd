class_name TongitsCardArtLibrary
extends RefCounted

# Tongits 默认牌面统一从 poker2 图集取得。UI 不应直接依赖图集坐标。
const CARD_ATLAS: Texture2D = preload("res://games/tongits/assets/cards/poker2.png")
const CARD_SIZE := Vector2i(112, 150)
const CELL_STEP := Vector2i(114, 152)
const CELL_PADDING := Vector2i(1, 1)

# TongitsCard 的花色顺序为梅花、方块、红桃、黑桃；图集编号顺序不同。
const SUIT_PREFIXES := [3, 4, 2, 1]

# poker2.plist 的 52 个 textureRect 均落在规则网格中，因此只保存网格坐标。
const FRAME_CELLS := {
	"101": Vector2i(0, 0),
	"102": Vector2i(0, 1),
	"103": Vector2i(1, 0),
	"104": Vector2i(0, 2),
	"105": Vector2i(1, 1),
	"106": Vector2i(2, 0),
	"107": Vector2i(0, 3),
	"108": Vector2i(1, 2),
	"109": Vector2i(2, 1),
	"110": Vector2i(3, 0),
	"111": Vector2i(0, 4),
	"112": Vector2i(1, 3),
	"113": Vector2i(2, 2),
	"201": Vector2i(3, 1),
	"202": Vector2i(0, 5),
	"203": Vector2i(1, 4),
	"204": Vector2i(2, 3),
	"205": Vector2i(3, 2),
	"206": Vector2i(0, 6),
	"207": Vector2i(1, 5),
	"208": Vector2i(2, 4),
	"209": Vector2i(3, 3),
	"210": Vector2i(0, 7),
	"211": Vector2i(1, 6),
	"212": Vector2i(2, 5),
	"213": Vector2i(3, 4),
	"301": Vector2i(0, 8),
	"302": Vector2i(1, 7),
	"303": Vector2i(2, 6),
	"304": Vector2i(3, 5),
	"305": Vector2i(0, 9),
	"306": Vector2i(1, 8),
	"307": Vector2i(2, 7),
	"308": Vector2i(3, 6),
	"309": Vector2i(0, 10),
	"310": Vector2i(1, 9),
	"311": Vector2i(2, 8),
	"312": Vector2i(3, 7),
	"313": Vector2i(0, 11),
	"401": Vector2i(1, 10),
	"402": Vector2i(2, 9),
	"403": Vector2i(3, 8),
	"404": Vector2i(0, 12),
	"405": Vector2i(1, 11),
	"406": Vector2i(2, 10),
	"407": Vector2i(3, 9),
	"408": Vector2i(1, 12),
	"409": Vector2i(2, 11),
	"410": Vector2i(3, 10),
	"411": Vector2i(2, 12),
	"412": Vector2i(3, 11),
	"413": Vector2i(3, 12),
}

static var _texture_cache: Dictionary = {}

static func texture_for(card: TongitsCard) -> AtlasTexture:
	if card == null or card.suit < 0 or card.suit >= SUIT_PREFIXES.size():
		return null
	var frame_code := "%d%02d" % [SUIT_PREFIXES[card.suit], card.rank]
	if not FRAME_CELLS.has(frame_code):
		return null
	if _texture_cache.has(frame_code):
		return _texture_cache[frame_code] as AtlasTexture

	var cell: Vector2i = FRAME_CELLS[frame_code]
	var texture := AtlasTexture.new()
	texture.atlas = CARD_ATLAS
	texture.region = Rect2(Vector2i(cell.x * CELL_STEP.x, cell.y * CELL_STEP.y) + CELL_PADDING, CARD_SIZE)
	_texture_cache[frame_code] = texture
	return texture

static func clear_cache() -> void:
	# 测试或主题切换时可以显式释放运行期创建的 AtlasTexture。
	_texture_cache.clear()
