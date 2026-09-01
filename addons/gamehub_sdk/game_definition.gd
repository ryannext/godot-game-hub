class_name GameDefinition
extends Resource

# GameDefinition 是 Hub 与独立游戏之间稳定的目录数据契约。
# 它只描述展示和启动信息，不应引用游戏内部的场景或业务脚本。
enum Availability {
	AVAILABLE,
	COMING_SOON,
	DISABLED,
}

enum DeliveryMode {
	BUILTIN,
	PCK,
}

@export_group("Identity")
@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var version := "1.0.0"

@export_group("Presentation")
@export var icon: Texture2D
@export var category := "其他"
@export var tags: PackedStringArray
@export var accent_color := Color("6c63ff")

@export_group("Launch")
@export var availability := Availability.AVAILABLE
# 编辑器与 PCK 发布必须使用同一个 res:// 入口路径。
@export_file("*.tscn") var entry_scene_path := ""
@export var delivery_mode := DeliveryMode.BUILTIN
# 开发期留空表示直接加载项目内资源；发布期可指向外部 PCK。
@export var pack_path := ""
@export_range(1, 16, 1) var min_players := 1
@export_range(1, 16, 1) var max_players := 1

func is_launchable() -> bool:
	return availability == Availability.AVAILABLE and not entry_scene_path.is_empty()

func availability_text() -> String:
	match availability:
		Availability.AVAILABLE:
			return "可游玩"
		Availability.COMING_SOON:
			return "即将推出"
		_:
			return "暂不可用"
