class_name PauseMenu
extends Control
## Shown while the game is paused.

var main: Main
var _first: Button
var _restart: Button
var _note: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(UiKit.centered(panel))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

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


func opened() -> void:
	# Together with a friend: the pause is for both, and only the host restarts.
	var together := Net.playing_together()
	_restart.visible = not together or Net.is_host()
	_note.text = "The game is paused for everybody. Coins so far are kept if you quit." if together \
			else "Coins collected so far are kept if you quit."
	_first.grab_focus()
