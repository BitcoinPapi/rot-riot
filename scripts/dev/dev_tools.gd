class_name DevTools
extends Node
## Developer helpers, only active when the game is started with extra
## command-line arguments after "--". Players never see this.
##
##   --shot=PATH        save a screenshot to PATH ...
##   --shot-frame=N     ... on frame N (default 30), then quit

var main: Node
var _args := {}
var _frame := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"


func _process(_delta: float) -> void:
	_frame += 1
	if _args.has("shot") and _frame == int(_args.get("shot-frame", "30")):
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(_args["shot"]))
		print("screenshot saved: ", _args["shot"], " ", img.get_size())
		get_tree().quit()
