class_name PauseMenu
extends Control
## Shown while the game is paused.

var main: Main
var _first: Button
var _restart: Button
var _note: Label
var _perks_side: VBoxContainer   # the perks chosen this run, beside the buttons (hidden while there are none)
var _perk_names: Label
var _perk_texts: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 34)
	panel.add_child(sides)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	sides.add_child(col)

	col.add_child(UiKit.heading("PAUSED", 60))
	col.add_child(UiKit.spacer(8))
	_first = UiKit.button("RESUME", func() -> void: main.resume_game())
	col.add_child(_first)
	col.add_child(UiKit.button("SETTINGS", func() -> void: main.open_screen("settings")))
	_restart = UiKit.button("RESTART RUN", func() -> void: main.restart_run())
	col.add_child(_restart)
	col.add_child(UiKit.button("QUIT TO MENU", func() -> void: main.quit_to_menu()))
	col.add_child(UiKit.spacer(2))
	_note = UiKit.heading("Coins collected so far are kept if you quit.", 15, UiKit.DIM)
	col.add_child(_note)

	# What the small symbols above the weapon panel mean: the perks of this run.
	_perks_side = VBoxContainer.new()
	_perks_side.add_theme_constant_override("separation", 10)
	_perks_side.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_child(_perks_side)
	_perks_side.add_child(UiKit.heading("YOUR PERKS THIS RUN", 22, UiKit.GOLD))
	var list := HBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	_perks_side.add_child(list)
	_perk_names = UiKit.label("", 16)
	_perk_texts = UiKit.label("", 16, UiKit.DIM)
	list.add_child(_perk_names)
	list.add_child(_perk_texts)


func opened() -> void:
	# Together with a friend: the pause is for both, and only the host restarts.
	var together := Net.playing_together()
	_restart.visible = not together or Net.is_host()
	_note.text = "The game is paused for everybody. Coins so far are kept if you quit." if together \
			else "Coins collected so far are kept if you quit."
	var names: Array[String] = []
	var texts: Array[String] = []
	if main.game != null and is_instance_valid(main.game):
		for id: String in Config.RUN_PERK_ORDER:
			var level := int(main.game.perks.get(id, 0))
			if level > 0:
				names.append(String(Config.RUN_PERKS[id]["name"]) + ("" if level == 1 else " " + Config.roman(level)))
				texts.append(Config.run_perk_text(id, level))
	_perks_side.visible = not names.is_empty()
	_perk_names.text = "\n".join(names)
	_perk_texts.text = "\n".join(texts)
	_first.grab_focus()
