class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --bot              a simple bot plays (through GameInput's virtual sticks)
##   --weapon=ID        the bot starts with this weapon (pistol, shotgun, ...)
##   --cycle            the bot is handed each weapon in turn every 6 seconds
##   --wave=N           jump straight to wave N
##   --god              the player cannot die
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
	if game != null and is_instance_valid(game):
		if _args.has("wave") and _frame == 2:
			game.director.wave = int(_args["wave"]) - 1
			game.director.intermission = 0.1
		if _args.has("god"):
			game.player.hp = game.player.max_hp
		if _args.has("bot"):
			_bot(game)
	if _args.has("shot") and _frame == int(_args.get("shot-frame", "30")):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(_args["shot"]))
		print("screenshot saved: ", _args["shot"], " ", img.get_size())
		get_tree().quit()
	if _args.has("frames") and _frame >= int(_args["frames"]):
		if game != null and is_instance_valid(game):
			print("SUMMARY frames=%d wave=%d kills=%d score=%d coins=%d alive=%d left=%d hp=%.0f rage=%.0f weapon=%s boss=%s state=%d" % [
				_frame, game.director.wave, game.kills, game.score, game.coins_run, game.enemies.alive_count,
				game.director.remaining(), game.player.hp, game.rage, game.player.weapon_id,
				str(game.director.boss_alive()), game.state])
		get_tree().quit()


func _bot(game: Game) -> void:
	var p := game.player
	if _args.has("weapon") and _frame == 2:
		p.give_weapon(String(_args["weapon"]))
	if _args.has("cycle") and _frame % 360 == 5:
		var order: Array = Config.WEAPON_ORDER
		p.give_weapon(String(order[(_frame / 360) % order.size()]))
	if game.rage_ready():
		GameInput.press_rage()
	var target := game.enemies.nearest(p.pos, 900.0)
	var aim := Vector2.RIGHT
	var fire := false
	var move := Vector2.from_angle(_frame * 0.013)
	if target != null:
		aim = (target.pos - p.pos).normalized()
		fire = true
		if target.pos.distance_to(p.pos) < 170.0:
			move = ((p.pos - target.pos).normalized() + move * 0.5).normalized()
		elif not game.pickups.crates.is_empty():
			move = (game.pickups.crates[0].pos - p.pos).normalized()
	GameInput.set_virtual_input(move, aim, fire)
