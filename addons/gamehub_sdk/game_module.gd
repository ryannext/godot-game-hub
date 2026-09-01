class_name GameModule
extends Control

# 所有内嵌游戏共享的最小生命周期契约。Hub 只依赖这里公开的信号和方法。
signal ready_to_play
signal exit_requested
signal game_finished(result: Dictionary)

var game_context: Dictionary = {}

func initialize(context: Dictionary) -> void:
	game_context = context.duplicate()

func start_game() -> void:
	ready_to_play.emit()

func pause_game() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED

func resume_game() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

func shutdown_game() -> void:
	pass
