class_name GameOverScreen
extends Control
## Results after the player dies.

var main: Main
var _title: Label
var _best: Label
var _values := {}     # stat name -> Label
var _coins: Label
var _buttons: Array[Button] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	_title = UiKit.heading("YOU GOT EATEN", 60, UiKit.RED)
	col.add_child(_title)
	_best = UiKit.heading("NEW BEST SCORE!", 24, UiKit.GOLD)
	col.add_child(_best)
	col.add_child(UiKit.spacer(4))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for stat: String in ["SCORE", "WAVE REACHED", "ZOMBIES KILLED", "TIME SURVIVED"]:
		grid.add_child(UiKit.label(stat, 22, UiKit.DIM))
		var value := UiKit.label("0", 26, UiKit.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(140, 0)
		grid.add_child(value)
		_values[stat] = value
	col.add_child(grid)

	col.add_child(UiKit.spacer(4))
	_coins = UiKit.heading("", 24, UiKit.GOLD)
	col.add_child(_coins)
	col.add_child(UiKit.spacer(8))

	_buttons.append(UiKit.button("PLAY AGAIN", func() -> void: main.start_run()))
	_buttons.append(UiKit.button("UPGRADES", func() -> void: main.open_screen("shop")))
	_buttons.append(UiKit.button("MAIN MENU", func() -> void: main.quit_to_menu()))
	for b: Button in _buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(b)


## Fill in the numbers for the run that just ended.
func show_results(stats: Dictionary, is_best: bool) -> void:
	_best.visible = is_best
	(_values["SCORE"] as Label).text = "%d" % int(stats.get("score", 0))
	(_values["WAVE REACHED"] as Label).text = "%d" % int(stats.get("wave", 0))
	(_values["ZOMBIES KILLED"] as Label).text = "%d" % int(stats.get("kills", 0))
	var seconds := int(stats.get("time", 0.0))
	(_values["TIME SURVIVED"] as Label).text = "%d:%02d" % [int(seconds / 60.0), seconds % 60]
	_coins.text = "+%d COINS   (you have %d)" % [int(stats.get("coins", 0)), SaveData.coins]
	# Ignore clicks for a moment so a held fire button doesn't press anything.
	for b: Button in _buttons:
		b.disabled = true
	get_tree().create_timer(0.7, true).timeout.connect(_unlock)


func _unlock() -> void:
	for b: Button in _buttons:
		b.disabled = false
	if visible:
		_buttons[0].grab_focus()


func opened() -> void:
	_coins.text = _coins.text.get_slice("(", 0) + "(you have %d)" % SaveData.coins
	if not _buttons[0].disabled:
		_buttons[0].grab_focus()
