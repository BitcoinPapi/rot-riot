class_name SettingsScreen
extends Control
## Volume, screen shake and fullscreen. Values live in SaveData.settings and
## are saved when you leave the screen.

var main: Main
var _sliders := {}       # setting key -> HSlider
var _value_labels := {}  # setting key -> Label
var _fullscreen: Button
var _back: Button
var _loading := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	col.add_child(UiKit.heading("SETTINGS", 54))
	col.add_child(UiKit.spacer(4))
	_add_slider(col, "master_volume", "MASTER VOLUME")
	_add_slider(col, "sfx_volume", "SOUND EFFECTS")
	_add_slider(col, "screen_shake", "SCREEN SHAKE")

	_fullscreen = UiKit.button("FULLSCREEN: OFF", func() -> void:
		SaveData.set_setting("fullscreen", not bool(SaveData.get_setting("fullscreen"))))
	col.add_child(_fullscreen)

	col.add_child(UiKit.spacer(6))
	_back = UiKit.button("BACK", func() -> void: main.close_screen())
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_back)

	SaveData.settings_changed.connect(_load_values)


func _add_slider(parent: Control, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var name_label := UiKit.label(title, 22)
	name_label.custom_minimum_size = Vector2(250, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(320, 34)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void:
		if _loading:
			return
		SaveData.settings[key] = value
		SaveData.apply_settings()
		_update_label(key)
		Sfx.play("ui_move", -4.0, 0.0))
	slider.mouse_entered.connect(func() -> void: slider.grab_focus())
	# Show clearly which row is selected (important with a gamepad).
	slider.focus_entered.connect(func() -> void: name_label.add_theme_color_override("font_color", UiKit.GOLD))
	slider.focus_exited.connect(func() -> void: name_label.add_theme_color_override("font_color", UiKit.TEXT))
	row.add_child(slider)

	var value_label := UiKit.label("100%", 22, UiKit.GOLD)
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	parent.add_child(row)
	_sliders[key] = slider
	_value_labels[key] = value_label


func _update_label(key: String) -> void:
	var label: Label = _value_labels[key]
	label.text = "%d%%" % int(round(float(SaveData.get_setting(key)) * 100.0))


func _load_values() -> void:
	_loading = true
	for key: String in _sliders.keys():
		var slider: HSlider = _sliders[key]
		slider.value = float(SaveData.get_setting(key))
		_update_label(key)
	_fullscreen.text = "FULLSCREEN: %s   (F11)" % ("ON" if bool(SaveData.get_setting("fullscreen")) else "OFF")
	_loading = false


func opened() -> void:
	_load_values()
	var first: HSlider = _sliders["master_volume"]
	first.grab_focus()


## Called by Main when the screen is left.
func closed() -> void:
	SaveData.save_game()
