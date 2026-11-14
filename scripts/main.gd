extends Node
## Entry point. Starts the game (menus arrive in a later stage).

var game: Game


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_run()
	if not OS.get_cmdline_user_args().is_empty():
		var dev := DevTools.new()
		dev.main = self
		add_child(dev)


func _start_run() -> void:
	game = Game.new()
	add_child(game)
	GameInput.set_gameplay_mode(true)
