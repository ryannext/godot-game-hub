extends VBoxContainer

# 当前设置仅作用于 Hub；独立游戏保留各自的音频和显示配置。
func _ready() -> void:
	%MasterSlider.value_changed.connect(_on_master_volume_changed)
	%FullscreenToggle.toggled.connect(_on_fullscreen_toggled)

func _on_master_volume_changed(value: float) -> void:
	# Slider 使用 0~100 线性值，AudioServer 需要分贝值。
	var bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value / 100.0))

func _on_fullscreen_toggled(enabled: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	)
