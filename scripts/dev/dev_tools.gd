class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --bot              a simple bot plays (through GameInput's virtual sticks)
##   --frames=N         quit after N frames and print a summary
##   --shot=PATH        save a screenshot to PATH ...
##   --shot-frame=N     ... on frame N (default 30), then quit

var main: Node
var _args := {}
var _frame := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"


func _process(_delta: float) -> void:
	_frame += 1
	var game: Game = main.get("game")
	if _args.has("bot") and game != null and is_instance_valid(game):
		_bot(game)
	if _args.has("shot") and _frame == int(_args.get("shot-frame", "30")):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(_args["shot"]))
		print("screenshot saved: ", _args["shot"], " ", img.get_size())
		get_tree().quit()
	if _args.has("frames") and _frame >= int(_args["frames"]):
		if game != null and is_instance_valid(game):
			print("SUMMARY frames=%d kills=%d alive=%d hp=%.0f state=%d" % [
				_frame, game.kills, game.enemies.alive_count, game.player.hp, game.state])
		get_tree().quit()


func _bot(game: Game) -> void:
	var p := game.player
	var target := game.enemies.nearest(p.pos, 900.0)
	var aim := Vector2.RIGHT
	var fire := false
	var move := Vector2.from_angle(_frame * 0.013)
	if target != null:
		aim = (target.pos - p.pos).normalized()
		fire = true
		if target.pos.distance_to(p.pos) < 170.0:
			move = ((p.pos - target.pos).normalized() + move * 0.5).normalized()
	GameInput.set_virtual_input(move, aim, fire)
