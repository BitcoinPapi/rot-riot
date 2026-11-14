class_name Main
extends Node
## Entry point and "app" state machine:
##
##   MENU  --Play-->  PLAYING  --Esc-->  PAUSED  --Resume-->  PLAYING
##     ^                 |                  |
##     |              (death)          Quit to menu
##     |                 v                  |
##     +---------- GAME_OVER <--------------+   (Play again -> PLAYING)
##
## Menus are Control screens on a CanvasLayer above the game. Sub-screens
## (Upgrades, Settings) are pushed on a small stack so "Back" always returns
## to wherever you came from.

enum State { MENU, PLAYING, PAUSED, GAME_OVER }

var state: int = State.MENU
var game: Game

var _ui_root: Control
var _background: MenuBackground
var _dim: ColorRect
var _screens := {}                 # name -> Control
var _stack: Array[String] = []     # open screens, last one is visible
var _dev_mode := false
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)   # we close the window ourselves, see quit_game()
	_build_ui()
	GameInput.pause_pressed.connect(_on_pause_pressed)
	GameInput.back_pressed.connect(_on_back_pressed)
	_enter_menu()

	# Developer / test helpers (only with extra command-line arguments).
	if not OS.get_cmdline_user_args().is_empty():
		_dev_mode = true
		var dev := DevTools.new()
		dev.main = self
		add_child(dev)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.theme = UiKit.make_theme()
	layer.add_child(_ui_root)

	_background = MenuBackground.new()
	_ui_root.add_child(_background)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(_dim)

	_add_screen("main", MainMenu.new())
	_add_screen("maps", MapScreen.new())
	_add_screen("character", CharacterScreen.new())
	_add_screen("armory", ArmoryScreen.new())
	_add_screen("settings", SettingsScreen.new())
	_add_screen("pause", PauseMenu.new())
	_add_screen("gameover", GameOverScreen.new())


func _add_screen(screen_name: String, screen: Control) -> void:
	screen.set("main", self)
	screen.visible = false
	_ui_root.add_child(screen)
	_screens[screen_name] = screen


# ----------------------------------------------------------------------------
#  Screen stack
# ----------------------------------------------------------------------------
func _show_only(screen_name: String) -> void:
	_stack.clear()
	_stack.append(screen_name)
	_refresh_screens()


## Open a sub-screen (Upgrades, Settings) on top of the current one.
func open_screen(screen_name: String) -> void:
	_stack.append(screen_name)
	_refresh_screens()


## Close the top sub-screen and go back.
func close_screen() -> void:
	if _stack.size() <= 1:
		return
	var leaving: Control = _screens[_stack.pop_back()]
	if leaving.has_method("closed"):
		leaving.call("closed")
	_refresh_screens()


func _refresh_screens() -> void:
	var top := "" if _stack.is_empty() else _stack[_stack.size() - 1]
	_ui_root.visible = not _stack.is_empty()
	_background.visible = state == State.MENU
	_dim.visible = state != State.MENU
	for screen_name: String in _screens.keys():
		var screen: Control = _screens[screen_name]
		screen.visible = screen_name == top
	if top != "":
		var current: Control = _screens[top]
		if current.has_method("opened"):
			current.call("opened")


# ----------------------------------------------------------------------------
#  State changes (called by the menu buttons)
# ----------------------------------------------------------------------------
func _enter_menu() -> void:
	state = State.MENU
	get_tree().paused = false
	GameInput.set_gameplay_mode(false)
	_show_only("main")


## Start a run on a map, from one of its unlocked starting waves. Without
## arguments it repeats the last choice (see the Play screen).
func start_run(map_index: int = -1, start_wave: int = -1) -> void:
	if map_index >= 0:
		if not SaveData.select_map(map_index, maxi(start_wave, 1)):
			SaveData.select_map(0, 1)
	_free_game()
	get_tree().paused = false
	state = State.PLAYING
	game = Game.new()
	game.map_index = SaveData.selected_map
	game.start_wave = SaveData.selected_start
	game.run_ended.connect(_on_run_ended)
	add_child(game)
	move_child(game, 0)
	_stack.clear()
	_refresh_screens()
	GameInput.set_gameplay_mode(true)


func restart_run() -> void:
	_bank_current_run()
	start_run()


func pause_game() -> void:
	if state != State.PLAYING or game == null or game.state != Game.State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	GameInput.set_gameplay_mode(false)
	_show_only("pause")


func resume_game() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	_stack.clear()
	_refresh_screens()
	GameInput.set_gameplay_mode(true)
	if game != null:
		game.player.hold_fire(0.2)


func quit_to_menu() -> void:
	_bank_current_run()
	_free_game()
	_enter_menu()


## Close the game cleanly: keep the coins, silence the audio, then exit.
func quit_game(exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	_bank_current_run()
	# Give the audio thread a moment to let go of the sounds that were still
	# playing, otherwise Godot prints "leaked instance" warnings on exit.
	get_tree().paused = true
	Sfx.stop_all()
	for i in 6:
		await get_tree().process_frame
		OS.delay_msec(40)
	get_tree().quit(exit_code)


func _on_run_ended(stats: Dictionary) -> void:
	var is_best := SaveData.record_run(stats)
	state = State.GAME_OVER
	game.hud.visible = false
	GameInput.set_gameplay_mode(false)
	var screen: GameOverScreen = _screens["gameover"]
	_show_only("gameover")
	screen.show_results(stats, is_best)
	Sfx.play("level_up" if bool(stats.get("victory", false)) else "game_over")


## Leaving a run early (quit / restart) still keeps the coins and score so far.
func _bank_current_run() -> void:
	if game != null and is_instance_valid(game) and game.state != Game.State.OVER and (state == State.PLAYING or state == State.PAUSED):
		SaveData.record_run(game.get_stats())


func _free_game() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	game = null


# ----------------------------------------------------------------------------
#  Pause / back buttons
# ----------------------------------------------------------------------------
func _on_pause_pressed() -> void:
	match state:
		State.PLAYING:
			pause_game()
		State.PAUSED:
			if _stack.size() > 1:
				close_screen()
			else:
				resume_game()
		_:
			close_screen()


func _on_back_pressed() -> void:
	if state == State.PLAYING:
		return
	if _stack.size() > 1:
		close_screen()
	elif state == State.PAUSED:
		resume_game()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Alt-tabbing away pauses the game instead of getting you killed.
			if not _dev_mode:
				pause_game()
		NOTIFICATION_WM_CLOSE_REQUEST:
			quit_game()
