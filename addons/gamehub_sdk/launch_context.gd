class_name GameHubLaunchContext
extends RefCounted

# 可选的强类型上下文包装器。GameHost 仍以 Dictionary 传递数据，
# 子游戏需要字段提示或单元测试时可以将 Dictionary 转为本对象。
var session_id := ""
var game_id: StringName
var locale := "zh_CN"
var data_directory := ""
var embedded := true

static func from_dictionary(values: Dictionary) -> GameHubLaunchContext:
	# 只读取 SDK 约定字段；游戏自有扩展字段继续保留在原始 Dictionary 中。
	var context := GameHubLaunchContext.new()
	context.session_id = str(values.get("session_id", ""))
	context.game_id = StringName(values.get("game_id", &""))
	context.locale = str(values.get("locale", "zh_CN"))
	context.data_directory = str(values.get("data_directory", ""))
	context.embedded = bool(values.get("embedded", true))
	return context

func is_valid() -> bool:
	return not game_id.is_empty() and not data_directory.is_empty()
